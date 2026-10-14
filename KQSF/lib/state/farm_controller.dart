import 'dart:async';

import 'package:flutter/material.dart';

import '../models/farm_telemetry.dart';
import '../models/telemetry_history.dart';
import '../services/mdns_service.dart';
import '../services/websocket_service.dart';

/// Owns everything the dashboard shows: the link to the gateway, the latest
/// telemetry, the trend window, and which tab is on screen.
///
/// This logic used to live inside the dashboard widget. Hoisting it here means
/// the two tabs share one connection, one history buffer and one theme choice,
/// and a rebuild triggered by a telemetry frame never disturbs the connection
/// bookkeeping around it.
class FarmController extends ChangeNotifier with WidgetsBindingObserver {
  FarmController({this.autoConnect = true});

  /// Whether to start connecting on construction. Tests turn this off.
  final bool autoConnect;

  static const Duration _initialRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(seconds: 15);

  /// Default TCP port the gateway listens on (`WS_PORT` in `gateway.py`).
  static const int defaultPort = 8765;

  /// Gateway address baked in at build time, bypassing discovery entirely.
  static const String configuredGateway =
      String.fromEnvironment('GATEWAY_ADDRESS');

  final MdnsDiscoveryService _discovery =
      MdnsDiscoveryService(timeout: Duration(seconds: 8));
  final FarmSocketService _socket = FarmSocketService();

  StreamSubscription<FarmTelemetry>? _telemetrySub;
  StreamSubscription<LinkState>? _stateSub;

  Timer? _retryTimer;
  Duration _retryDelay = _initialRetryDelay;

  FarmTelemetry _telemetry = FarmTelemetry.initial();
  LinkState _link = LinkState.idle;
  String _statusMessage = 'Starting up…';
  String _gatewayLabel = '';
  DateTime? _lastFrameAt;

  /// True when the current link was built from an advertised hostname instead
  /// of a verified address, which is unreliable on Windows.
  bool _hostnameOnly = false;

  /// When set, the app connects straight to this `host` or `host:port` and
  /// skips mDNS entirely. Needed on the web build, which has no mDNS
  /// implementation, and on networks that block multicast.
  String? _manualAddress;

  /// Rolling window backing the sparklines.
  final TelemetryHistory history = TelemetryHistory();

  /// Messages describing commands that could not be written, drained by the
  /// shell to show a snack bar.
  final List<String> _commandErrors = <String>[];

  ThemeMode _themeMode = ThemeMode.system;
  int _tabIndex = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Observable state
  // ---------------------------------------------------------------------------

  FarmTelemetry get telemetry => _telemetry;

  LinkState get link => _link;

  String get statusMessage => _statusMessage;

  /// The gateway address the app is dialling, empty until one is resolved.
  String get gatewayLabel => _gatewayLabel;

  DateTime? get lastFrameAt => _lastFrameAt;

  /// Description of the most recent malformed frame, if any.
  String get frameError => _socket.lastFrameError;

  /// Whether the gateway was reached through an advertised hostname, which
  /// Windows cannot resolve reliably.
  bool get hostnameOnly => _hostnameOnly;

  ThemeMode get themeMode => _themeMode;

  int get tabIndex => _tabIndex;

  /// Whether the socket is up and telemetry is flowing.
  bool get isOnline => _link == LinkState.online;

  /// Whether a connection attempt is currently in flight.
  bool get isBusy => _link == LinkState.discovering ||
      _link == LinkState.connecting ||
      _link == LinkState.reconnecting;

  /// Address to dial, preferring the in-app override over the build-time one.
  String? get effectiveAddress =>
      _manualAddress ?? (configuredGateway.isEmpty ? null : configuredGateway);

  bool get usingManualAddress => effectiveAddress != null;

  /// Whether any telemetry has ever arrived, so the UI can tell "no reading
  /// yet" apart from a genuine zero.
  bool get hasReading => _lastFrameAt != null;

  /// Whether the link is up but telemetry has stopped, which the socket's
  /// heartbeat watchdog normally catches before the UI does.
  bool get isStale =>
      _link == LinkState.online &&
      _lastFrameAt != null &&
      DateTime.now().difference(_lastFrameAt!) > const Duration(seconds: 6);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Begins listening and, unless disabled, starts the first connection.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _telemetrySub = _socket.telemetry.listen(_onTelemetry);
    _stateSub = _socket.stateChanges.listen(_onStateChanged);
    if (autoConnect) {
      unawaited(ensureSession());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_link != LinkState.online) unawaited(ensureSession());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Cancel the pending retry first, otherwise it fires while
        // backgrounded and races the session that `resumed` starts, leaving two
        // discoveries competing for Android's NSD operation budget.
        _retryTimer?.cancel();
        _retryTimer = null;
        // Stop discovery while backgrounded, as the plugin docs recommend.
        unawaited(_discovery.cancel());
        unawaited(_socket.disconnect());
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    unawaited(_telemetrySub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_discovery.dispose());
    unawaited(_socket.dispose());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  /// Monotonic id for the newest session attempt.
  ///
  /// [ensureSession] can be entered several times over in quick succession
  /// (from [start], from a `resumed` lifecycle event, from the retry timer and
  /// from the refresh button). Each attempt ends in `FarmSocketService
  /// .connect`, which closes any existing socket first, so two overlapping
  /// attempts make the app connect and immediately hang up again. Every attempt
  /// therefore carries an id and abandons itself as soon as it is no longer the
  /// newest.
  int _session = 0;

  /// Whether [session] has been overtaken by a newer attempt or torn down.
  bool _superseded(int session) => _disposed || session != _session;

  /// Brings the app online: discover, connect, and keep retrying until it works.
  Future<void> ensureSession() async {
    final int session = ++_session;
    _retryTimer?.cancel();
    if (_disposed) return;

    // A pinned address short-circuits discovery: the web build has no mDNS
    // implementation, and some routers block multicast outright.
    final String? pinned = effectiveAddress;
    if (pinned != null) {
      await _connectTo(pinned, session: session);
      return;
    }

    _set(link: LinkState.discovering, message: 'Scanning for the gateway…');

    GatewayEndpoint? endpoint;
    try {
      endpoint = await _discovery.discover();
    } on DiscoveryFailure catch (failure) {
      if (_superseded(session)) return;
      _fail(failure.message);
      return;
    }

    if (_superseded(session)) return;

    if (endpoint == null) {
      _fail('No gateway found on ${MdnsDiscoveryService.defaultFqdn}');
      return;
    }

    _hostnameOnly = endpoint.fromHostname;

    await _connectTo(endpoint.host, port: endpoint.port, session: session);
  }

  Future<void> _connectTo(
    String target, {
    int port = defaultPort,
    required int session,
  }) async {
    final GatewayAddress address = _parseAddress(target, port);
    _set(
      link: LinkState.connecting,
      message: 'Connecting to ${address.display}…',
      gateway: address.display,
    );

    try {
      await _socket.connect(address);
      if (_superseded(session)) return;
      _retryDelay = _initialRetryDelay;
      _set(link: LinkState.online, message: 'Live');
    } on CommandFailure catch (failure) {
      if (_superseded(session)) return;
      _fail(failure.message);
    } on Object catch (error) {
      if (_superseded(session)) return;
      _fail('Unexpected connection error: $error');
    }
  }

  /// Schedules a retry with exponential backoff.
  void _fail(String message) {
    if (_disposed) return;
    // A gap in the feed must not be drawn as one continuous trend, so the
    // window restarts with the new session.
    history.clear();
    _lastFrameAt = null;
    _set(link: LinkState.reconnecting, message: message);

    final int session = _session;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (_superseded(session)) return;
      unawaited(ensureSession());
    });

    final Duration next = _retryDelay * 2;
    _retryDelay = next > _maxRetryDelay ? _maxRetryDelay : next;
  }

  /// Reacts to the socket layer's own view of the link.
  ///
  /// The socket only reports `offline` when it drops from `connecting` or
  /// `online`. An `online -> offline` edge is therefore a genuine loss and has
  /// to schedule a retry; anything else is the teardown this controller already
  /// knows about, and overwriting the status with it would hide the more useful
  /// "scanning" or "reconnecting" message.
  void _onStateChanged(LinkState state) {
    if (_disposed) return;

    if (state == LinkState.offline) {
      if (_link == LinkState.online) {
        _fail('Connection lost. Reconnecting…');
      }
      return;
    }
    _set(link: state);
  }

  void _onTelemetry(FarmTelemetry frame) {
    if (_disposed) return;
    _telemetry = frame;
    _lastFrameAt = DateTime.now();
    history.add(frame);
    notifyListeners();
  }

  void _set({required LinkState link, String? message, String? gateway}) {
    if (_disposed) return;
    _link = link;
    if (message != null) _statusMessage = message;
    if (gateway != null) _gatewayLabel = gateway;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  /// Writes [command] to the socket, queueing [message] for the user if the
  /// link is down or the write fails.
  void _send(Map<String, dynamic> command) {
    unawaited(() async {
      try {
        final bool sent = await _socket.sendCommand(command);
        if (!sent) _queueError('Not connected — command was not sent.');
      } on CommandFailure catch (failure) {
        _queueError(failure.message);
      }
    }());
  }

  void _queueError(String message) {
    if (_disposed) return;
    // Bound the queue: a repeated failure while offline should not grow without
    // limit behind a backlog of snack bars the user will never see.
    if (_commandErrors.length >= 3) _commandErrors.removeAt(0);
    _commandErrors.add(message);
    notifyListeners();
  }

  /// Switches Pump 1 between automatic and manual control.
  void setPump1Auto(bool auto) =>
      _send(FarmTelemetry.pump1AutoCommand(auto));

  /// Drives Pump 1 by hand, which implicitly leaves auto mode.
  void setPump1Power(bool on) =>
      _send(FarmTelemetry.pump1Command(auto: false, state: on));

  void setPump2Power(bool on) => _send(FarmTelemetry.pump2Command(on));

  void setServoAuto(bool auto) =>
      _send(FarmTelemetry.servoAutoCommand(auto));

  void setServoAngle(int degrees) => _send(
        FarmTelemetry.servoCommand(auto: false, angle: degrees.toDouble()),
      );

  /// Removes and returns the oldest pending command error, or `null`.
  String? takeCommandError() =>
      _commandErrors.isEmpty ? null : _commandErrors.removeAt(0);

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  /// Switches to whichever of light or dark is *not* currently on screen, so a
  /// single tap always does the obvious thing instead of cycling.
  void toggleTheme(Brightness current) {
    setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Sets the theme explicitly, and is the seam tests use to pin a look.
  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index == _tabIndex || index < 0 || index > 1) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Pins the gateway address, or clears the pin when [address] is `null`.
  Future<void> useAddress(String? address) async {
    _manualAddress = address;
    _retryTimer?.cancel();
    await ensureSession();
  }

  static GatewayAddress _parseAddress(String raw, int defaultPort) {
    final String value = raw.trim();
    final int colon = value.lastIndexOf(':');
    if (colon > 0 && int.tryParse(value.substring(colon + 1)) != null) {
      return GatewayAddress(
        host: value.substring(0, colon),
        port: int.parse(value.substring(colon + 1)),
      );
    }
    return GatewayAddress(host: value, port: defaultPort);
  }
}