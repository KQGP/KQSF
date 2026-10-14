// End-to-end test for the socket layer.
//
// Runs a real WebSocket server that behaves like `gateway.py` (broadcasting one
// telemetry document per second and echoing commands back) and drives
// [FarmSocketService] against it over TCP. This covers the parts a fake cannot:
// the handshake, `ready` failure reporting, frame decoding and command framing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/models/farm_telemetry.dart';
import 'package:smart_farm/services/mdns_service.dart';
import 'package:smart_farm/services/websocket_service.dart';

/// Stand-in for the Python gateway, built on dart:io's WebSocketTransformer.
class FakeGateway {
  FakeGateway._(this._server);

  final HttpServer _server;
  final StreamController<String> commands = StreamController<String>.broadcast();
  WebSocket? _client;
  Completer<void>? _clientReady;
  bool _closed = false;

  /// Commands received from the client, as raw JSON strings.
  Stream<String> get commandStream => commands.stream;

  static Future<FakeGateway> start() async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final FakeGateway gateway = FakeGateway._(server);
    unawaited(gateway._serve());
    return gateway;
  }

  int get port => _server.port;

  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      _client = socket;
      final Completer<void>? ready = _clientReady;
      if (ready != null && !ready.isCompleted) ready.complete();
      socket.listen(
        (Object? message) {
          if (message is String) commands.add(message);
        },
        onDone: () => _client = null,
        onError: (Object _) => _client = null,
      );
    }
  }

  /// Completes once a client has finished its handshake.
  ///
  /// The client's `ready` future resolves as soon as it sees the 101 response,
  /// which can happen before the server side has finished `upgrade`, so a test
  /// must wait for this before pushing frames.
  Future<void> waitForClient({Duration timeout = const Duration(seconds: 5)}) {
    final WebSocket? existing = _client;
    if (existing != null) return Future<void>.value();

    final Completer<void> completer = Completer<void>();
    _clientReady = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () => throw StateError('No client connected in time'),
    );
  }

  /// Pushes a telemetry document to the connected client.
  void broadcast(Object json) {
    final WebSocket? client = _client;
    if (client == null) {
      throw StateError('broadcast called with no client attached');
    }
    client.add(json);
  }

  /// Closes the client connection without shutting the listener down, which is
  /// how the link dies when the phone leaves Wi-Fi range.
  Future<void> dropClient() async {
    await waitForClient();
    final WebSocket? client = _client;
    _client = null;
    await client?.close();
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    await _client?.close();
    _client = null;
    await _server.close(force: true);
    await commands.close();
  }
}

void main() {
  setUpAll(() {
    // flutter_test installs a global HttpOverrides that answers every request
    // with a canned failure, which blocks the real TCP socket exercised here.
    // Restoring the platform default lets the loopback server be reached.
    HttpOverrides.global = null;
  });

  group('FarmSocketService over a real socket', () {
    late FakeGateway gateway;
    late FarmSocketService socket;

    setUp(() async {
      gateway = await FakeGateway.start();
      socket = FarmSocketService(connectTimeout: const Duration(seconds: 5));
    });

    tearDown(() async {
      await socket.dispose();
      await gateway.stop();
    });

    test('connects, streams telemetry and sends commands', () async {
      await socket.connect(GatewayAddress(host: '127.0.0.1', port: gateway.port));
      await gateway.waitForClient();
      expect(socket.state, LinkState.online);

      final Future<FarmTelemetry> nextFrame =
          socket.telemetry.first.timeout(const Duration(seconds: 5));
      gateway.broadcast(
        jsonEncode(<String, dynamic>{
          'soil': 512,
          'rain': 210,
          'temp': 24.5,
          'hum': 58,
          'p1_auto': true,
          'p1_state': false,
          'p2_auto': false,
          'p2_state': false,
          'servo_auto': true,
          'servo_angle': 90,
        }),
      );

      final FarmTelemetry telemetry = await nextFrame;
      expect(telemetry.soil, 512);
      expect(telemetry.rain, 210);
      expect(telemetry.temp, closeTo(24.5, 1e-9));
      expect(telemetry.servoAngle, closeTo(90, 1e-9));

      // A command must reach the wire as one JSON object.
      final Future<String> command =
          gateway.commandStream.first.timeout(const Duration(seconds: 5));
      final bool sent = await socket.sendCommand(
        FarmTelemetry.pump1Command(auto: false, state: true),
      );
      expect(sent, isTrue);

      expect(jsonDecode(await command), <String, dynamic>{
        'p1_auto': false,
        'p1_state': true,
      });
    });

    test('recovers several frames coalesced into one message', () async {
      await socket.connect(GatewayAddress(host: '127.0.0.1', port: gateway.port));
      await gateway.waitForClient();

      final Future<List<FarmTelemetry>> three =
          socket.telemetry.take(3).toList().timeout(const Duration(seconds: 5));

      gateway.broadcast('{"soil":1}{"soil":2}{"soil":3}');

      final List<FarmTelemetry> frames = await three;
      expect(frames.map((FarmTelemetry f) => f.soil), <int>[1, 2, 3]);
    });

    test('ignores binary frames without tearing the link down', () async {
      await socket.connect(GatewayAddress(host: '127.0.0.1', port: gateway.port));
      await gateway.waitForClient();

      final Future<FarmTelemetry> frame =
          socket.telemetry.first.timeout(const Duration(seconds: 5));
      gateway.broadcast(utf8.encode('{"soil":777}'));

      expect((await frame).soil, 777);
      expect(socket.state, LinkState.online);
    });

    test('refuses commands while offline instead of throwing', () async {
      final bool sent = await socket.sendCommand(
        FarmTelemetry.pump2Command(true),
      );
      expect(sent, isFalse);
    });

    test('reports offline when the gateway hangs up', () async {
      final Future<LinkState> offline = socket.stateChanges
          .firstWhere((LinkState s) => s == LinkState.offline)
          .timeout(const Duration(seconds: 5));

      await socket.connect(GatewayAddress(host: '127.0.0.1', port: gateway.port));
      await gateway.dropClient();

      expect(await offline, LinkState.offline);
      expect(socket.isConnected, isFalse);
    });

    test('fails fast when nothing is listening on the port', () async {
      // Take a port and release it so the connection is refused.
      final int deadPort = gateway.port;
      await gateway.stop();

      Object? failure;
      try {
        await socket.connect(GatewayAddress(host: '127.0.0.1', port: deadPort));
      } on CommandFailure catch (error) {
        failure = error;
      }

      expect(failure, isA<CommandFailure>());
      expect(socket.state, LinkState.offline);
      expect(socket.isConnected, isFalse);

      // Restart so tearDown has something to close.
      gateway = await FakeGateway.start();
    });

    test('a reconnect converges to one stable online session', () async {
      await socket.connect(
        GatewayAddress(host: '127.0.0.1', port: gateway.port),
      );
      await gateway.waitForClient();

      // Reproduces the startup flapping seen on desktop: a second attempt is
      // issued while the first is still settling. It must settle on a single
      // live link rather than bouncing.
      await socket.connect(
        GatewayAddress(host: '127.0.0.1', port: gateway.port),
      );
      await gateway.waitForClient();

      expect(socket.state, LinkState.online);
      expect(socket.isConnected, isTrue);

      // Telemetry must still flow on the surviving connection.
      final Future<FarmTelemetry> frame =
          socket.telemetry.first.timeout(const Duration(seconds: 5));
      gateway.broadcast('{"soil":512}');
      expect((await frame).soil, 512);

      // And the link must stay up rather than dropping again.
      final List<LinkState> after = <LinkState>[];
      final sub = socket.stateChanges.listen(after.add);
      gateway.broadcast('{"soil":513}');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      expect(after, isEmpty, reason: 'the session should be stable');
      expect(socket.state, LinkState.online);
    });

    test('a stale socket is torn down when telemetry stops', () async {
      await socket.connect(
        GatewayAddress(host: '127.0.0.1', port: gateway.port),
      );
      await gateway.waitForClient();

      final Future<FarmTelemetry> first =
          socket.telemetry.first.timeout(const Duration(seconds: 5));
      gateway.broadcast('{"soil":1}');
      await first;

      // Nothing further is broadcast, so the watchdog must eventually take the
      // session down. Its budget is 2 x 5s; allow headroom for the timer.
      final Future<LinkState> offline = socket.stateChanges
          .firstWhere((LinkState s) => s == LinkState.offline)
          .timeout(const Duration(seconds: 20));

      expect(await offline, LinkState.offline);
    });
  });

  group('MdnsDiscoveryService address handling', () {
    test('recognises address literals but not hostnames', () {
      expect(MdnsDiscoveryService.asIpLiteral('192.168.1.42'), '192.168.1.42');
      expect(MdnsDiscoveryService.asIpLiteral(' 10.0.0.7 '), '10.0.0.7');
      expect(MdnsDiscoveryService.asIpLiteral('fe80::1'), 'fe80::1');
      expect(MdnsDiscoveryService.asIpLiteral('[::1]'), '::1');

      expect(MdnsDiscoveryService.asIpLiteral('smartfarm.local'), isNull);
      expect(MdnsDiscoveryService.asIpLiteral('gateway'), isNull);
      expect(MdnsDiscoveryService.asIpLiteral(''), isNull);
      // Out-of-range octets and stray ports are not addresses.
      expect(MdnsDiscoveryService.asIpLiteral('192.168.1.999'), isNull);
      expect(MdnsDiscoveryService.asIpLiteral('192.168.1'), isNull);
      expect(MdnsDiscoveryService.asIpLiteral('smartfarm.local:8765'), isNull);
    });

    test('reads the gateway address out of the TXT record', () {
      // Mirrors the format gateway.py advertises.
      Map<String, List<int>> txt(String ip) =>
          <String, List<int>>{'version': utf8.encode('1.0'), 'ip': utf8.encode(ip)};

      expect(MdnsDiscoveryService.addressFromTxtForTest(txt('192.168.8.74')),
          '192.168.8.74');
      expect(
        MdnsDiscoveryService.addressFromTxtForTest(txt('192.168.8.74:8765')),
        '192.168.8.74',
      );
      // A hostname in the record is not usable as an address.
      expect(
        MdnsDiscoveryService.addressFromTxtForTest(txt('smartfarm.local')),
        isNull,
      );
      expect(MdnsDiscoveryService.addressFromTxtForTest(null), isNull);
      expect(
        MdnsDiscoveryService.addressFromTxtForTest(
          <String, List<int>>{'version': utf8.encode('1.0')},
        ),
        isNull,
      );
    });
  });

  group('GatewayAddress', () {
    test('brackets bare IPv6 literals', () {
      expect(
        const GatewayAddress(host: 'fe80::1', port: 8765).uri.toString(),
        'ws://[fe80::1]:8765',
      );
      expect(
        const GatewayAddress(host: '[fe80::1]', port: 8765).uri.toString(),
        'ws://[fe80::1]:8765',
      );
    });

    test('leaves IPv4 and hostnames alone', () {
      expect(
        const GatewayAddress(host: '192.168.1.42', port: 8765).uri.toString(),
        'ws://192.168.1.42:8765',
      );
      expect(
        const GatewayAddress(host: 'smartfarm.local', port: 8765)
            .uri
            .toString(),
        'ws://smartfarm.local:8765',
      );
    });
  });
}