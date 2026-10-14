import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/farm_telemetry.dart';

/// Lifecycle of the link to the gateway.
enum LinkState {
  /// Nothing scheduled yet.
  idle,

  /// Looking for the gateway on the local network.
  discovering,

  /// Opening the WebSocket.
  connecting,

  /// Socket is open and telemetry is flowing.
  online,

  /// Link lost; a retry is scheduled.
  reconnecting,

  /// Deliberately disconnected, or every attempt failed.
  offline,
}

/// Thrown when a command could not be written to the socket.
class CommandFailure implements Exception {
  const CommandFailure(this.message);

  final String message;

  @override
  String toString() => 'CommandFailure: $message';
}

/// Maintains the WebSocket link to the gateway and turns the raw telemetry
/// frames it pushes into typed [FarmTelemetry] values.
///
/// The gateway (`gateway.py`) broadcasts one JSON document per second for as
/// long as at least one client is connected, and forwards anything the app
/// sends straight to the board with a trailing newline. The board reads a
/// single document per loop iteration, so this class deliberately leaves frame
/// pacing to the caller and never fans a burst of messages out on its own.
class FarmSocketService {
  FarmSocketService({this.connectTimeout = const Duration(seconds: 8)});

  /// How long to wait for the opening handshake before giving up.
  final Duration connectTimeout;

  final StreamController<FarmTelemetry> _telemetry =
      StreamController<FarmTelemetry>.broadcast();
  final StreamController<LinkState> _stateChanges =
      StreamController<LinkState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatWatchdog;

  LinkState _state = LinkState.idle;
  bool _disposed = false;
  int _generation = 0;
  String _lastFrameError = '';

  /// Telemetry frames, newest last. Broadcast, so several listeners are safe.
  Stream<FarmTelemetry> get telemetry => _telemetry.stream;

  /// Current link state, replayed to new listeners on subscription.
  Stream<LinkState> get stateChanges => _stateChanges.stream;

  LinkState get state => _state;

  bool get isConnected => _state == LinkState.online;

  /// Description of the most recent malformed frame, surfaced in the UI so a
  /// silent protocol mismatch is visible rather than mysterious.
  String get lastFrameError => _lastFrameError;

  /// Opens the socket to `ws://host:port`.
  ///
  /// Completes once the handshake succeeds, and throws when the gateway cannot
  /// be reached. Safe to call while already connected: the existing socket is
  /// closed first.
  Future<void> connect(GatewayAddress address) async {
    if (_disposed) {
      throw const CommandFailure('The socket service has been disposed.');
    }

    await disconnect();

    final int generation = ++_generation;
    _lastFrameError = '';
    // Clear the previous session's heartbeat: leaving it set would make the
    // watchdog judge the new connection stale the instant it comes online.
    _lastFrameAtMs = 0;
    _setState(LinkState.connecting);

    // `WebSocketChannel.connect` returns before the handshake completes and
    // reports failures through `ready`, so the failure has to be awaited here
    // rather than caught around the constructor call.
    final Uri uri = address.uri;
    try {
      final WebSocketChannel channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        (dynamic frame) => _handleFrame(frame, generation),
        onError: (Object error, StackTrace stackTrace) =>
            _handleTransportError(error, generation),
        onDone: () => _handleTransportClosed(generation),
        cancelOnError: false,
      );

      // Keep the watchdog running for the whole session, not just the
      // handshake: a phone that walks out of Wi-Fi range keeps a half-open TCP
      // socket that never errors, so only a missing data flow reveals it.
      _heartbeatWatchdog = Timer.periodic(
        _heartbeatPeriod,
        (_) => _checkStale(generation),
      );

      await channel.ready.timeout(connectTimeout);
      if (_cancelled(generation)) {
        await _closeChannel();
        return;
      }
      _setState(LinkState.online);
    } on Object catch (error) {
      if (_cancelled(generation)) {
        await _closeChannel();
        return;
      }
      await _closeChannel();
      _setState(LinkState.offline);
      throw CommandFailure(_describeConnectFailure(error, address));
    }
  }

  /// Sends a command object to the board.
  ///
  /// Returns `false` when the socket is not currently connected, so callers can
  /// ignore a tap made while the link is down instead of throwing.
  Future<bool> sendCommand(Map<String, dynamic> command) async {
    final WebSocketChannel? channel = _channel;
    if (_disposed || channel == null || _state != LinkState.online) return false;

    try {
      channel.sink.add(jsonEncode(command));
      return true;
    } on Object catch (error) {
      throw CommandFailure('Could not send ${command.keys.join(', ')}: $error');
    }
  }

  /// Closes the socket without tearing the service down.
  Future<void> disconnect() async {
    _generation++;
    await _closeChannel();
    if (_disposed) return;

    // Only report a transition out of a state that implied a live link. A
    // teardown from idle/discovering is not a disconnection, and emitting one
    // would make the stream claim a failure that never happened.
    if (_state == LinkState.connecting || _state == LinkState.online) {
      _setState(LinkState.offline);
    }
  }

  /// Releases every resource. The service is unusable afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _closeChannel();
    await _telemetry.close();
    await _stateChanges.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// How often to confirm telemetry is still arriving.
  static const Duration _heartbeatPeriod = Duration(seconds: 5);

  /// Frames are produced by the board once a second, so two missed intervals
  /// means the link is gone even though the socket never reported an error.
  static const int _missedHeartbeats = 2;

  int _lastFrameAtMs = 0;

  /// True when [generation] is stale, i.e. the caller has been superseded.
  bool _cancelled(int generation) => _disposed || generation != _generation;

  Future<void> _closeChannel() async {
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = null;

    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      // Errors from the cancelled stream must not escape as unhandled.
      unawaited(subscription.cancel().catchError((Object _) {}));
    }

    final WebSocketChannel? channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close(ws_status.normalClosure).timeout(
              const Duration(seconds: 2),
            );
      } on Object {
        // Closing an already broken socket is not an error worth surfacing.
      }
    }
  }

  void _setState(LinkState next) {
    if (_disposed || _state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) _stateChanges.add(next);
  }

  /// Decodes one inbound frame and publishes the telemetry.
  void _handleFrame(dynamic frame, int generation) {
    if (_cancelled(generation)) return;

    final String? text = _decodeFrame(frame);
    if (text == null) return;

    _lastFrameAtMs = DateTime.now().millisecondsSinceEpoch;

    // The gateway forwards whole lines, but tolerate several documents or a
    // truncated tail inside a single frame rather than dropping the lot.
    for (final String document in splitJsonDocuments(text)) {
      final Object? decoded;
      try {
        decoded = jsonDecode(document);
      } on FormatException catch (error) {
        _note('Dropped a malformed telemetry frame: ${error.message}');
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        _note('Dropped a telemetry frame that was not a JSON object.');
        continue;
      }
      if (!_telemetry.isClosed) {
        _telemetry.add(FarmTelemetry.fromJson(decoded));
      }
    }
  }

  /// Normalises a WebSocket payload to text, tolerating binary frames.
  static String? _decodeFrame(dynamic frame) {
    if (frame is String) return frame;
    if (frame is List<int>) {
      try {
        return utf8.decode(frame);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Splits a frame into the balanced top-level JSON objects it contains.
  ///
  /// The gateway sends one document per WebSocket message, but a firmware
  /// change or a coalesced read can deliver several, plus a truncated tail.
  /// An incomplete object is dropped rather than parsed. Strings are tracked
  /// so a brace inside a value cannot throw the depth counter off.
  static List<String> splitJsonDocuments(String text) {
    final List<String> documents = <String>[];
    int depth = 0;
    int start = -1;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < text.length; i++) {
      final String char = text[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      switch (char) {
        case '"':
          inString = true;
        case '{':
          if (depth == 0) start = i;
          depth++;
        case '}':
          if (depth > 0) {
            depth--;
            if (depth == 0 && start >= 0) {
              documents.add(text.substring(start, i + 1));
              start = -1;
            }
          }
      }
    }
    return documents;
  }

  void _note(String message) {
    _lastFrameError = message;
  }

  void _handleTransportError(Object error, int generation) {
    if (_cancelled(generation)) return;
    _note('Link error: $error');
    _setState(LinkState.offline);
  }

  void _handleTransportClosed(int generation) {
    if (_cancelled(generation)) return;
    _setState(LinkState.offline);
  }

  /// Fails the session when telemetry stops arriving over an otherwise silent
  /// socket, which is what a dropped Wi-Fi connection looks like on mobile.
  void _checkStale(int generation) {
    if (_cancelled(generation)) return;
    if (_state != LinkState.online) return;
    // The handshake may still be in flight; give it room before judging.
    if (_lastFrameAtMs == 0) return;

    final int elapsed = DateTime.now().millisecondsSinceEpoch - _lastFrameAtMs;
    final int budget =
        _heartbeatPeriod.inMilliseconds * _missedHeartbeats;
    if (elapsed > budget) {
      _note('No telemetry received for ${elapsed ~/ 1000}s. Reconnecting.');
      unawaited(disconnect());
    }
  }

  static String _describeConnectFailure(Object error, GatewayAddress address) {
    final String text = error.toString();
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException') && text.contains('11001')) {
      return 'The system could not resolve "${address.host}". This gateway '
          'advertises a .local name that Windows cannot look up; enter the '
          'gateway IP address instead.';
    }
    if (text.contains('Failed host lookup') || text.contains('SocketException')) {
      return 'Could not reach ${address.display}. Check the Wi-Fi network.';
    }
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return 'The gateway at ${address.display} did not answer in time.';
    }
    if (text.contains('Connection refused')) {
      return '${address.display} refused the connection. Is the gateway '
          'running?';
    }
    return 'Could not connect to ${address.display}.';
  }
}

/// A host/port pair to connect to.
class GatewayAddress {
  const GatewayAddress({required this.host, required this.port});

  final String host;
  final int port;

  String get display => '$host:$port';

  /// Builds a `ws://` URI, bracketing bare IPv6 literals.
  Uri get uri {
    final String authority = host.trim();
    if (authority.startsWith('[') && authority.endsWith(']')) {
      // Already bracketed; do not double wrap.
      return Uri.parse('ws://$authority:$port');
    }
    if (authority.contains(':')) {
      // A bare IPv6 literal such as `fe80::1` is ambiguous without brackets.
      return Uri.parse('ws://[$authority]:$port');
    }
    return Uri.parse('ws://$authority:$port');
  }
}