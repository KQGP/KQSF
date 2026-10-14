import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:nsd/nsd.dart';

/// A resolved address of the Smart Farm gateway.
class GatewayEndpoint {
  const GatewayEndpoint({
    required this.host,
    required this.port,
    this.name,
    this.addresses = const <String>[],
    this.fromHostname = false,
  });

  /// Host to open the WebSocket against. Prefer an IPv4 literal (see
  /// `MdnsDiscoveryService._endpointFrom`) so the app never depends on the
  /// phone being able to resolve a `.local.` hostname.
  final String host;

  /// TCP port the gateway's WebSocket server listens on.
  final int port;

  /// Advertised mDNS instance name, used for display only.
  final String? name;

  /// Every address the resolver returned, in priority order.
  final List<String> addresses;

  /// True when [host] is an advertised name rather than a verified address.
  ///
  /// A `.local` name is not resolvable by the ordinary system resolver on every
  /// platform (Windows returns `WSAHOST_NOT_FOUND`), so a link opened this way
  /// is fragile and the UI says so.
  final bool fromHostname;

  /// `host:port`, used in the UI.
  String get display => '$host:$port';

  @override
  String toString() => 'GatewayEndpoint($display, name: $name)';

  @override
  bool operator ==(Object other) =>
      other is GatewayEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Raised when discovery cannot complete; carries a message safe to show.
class DiscoveryFailure implements Exception {
  const DiscoveryFailure(this.message);

  final String message;

  @override
  String toString() => 'DiscoveryFailure: $message';
}

/// Locates the gateway by browsing for the `_smartfarm._tcp` service type that
/// `gateway.py` advertises through Zeroconf.
///
/// The instance owns exactly one native discovery at a time: Android caps
/// concurrent NSD operations (around ten) and fails with
/// [ErrorCause.maxLimit] beyond that, so a leaked discovery would break every
/// later scan. [dispose] and [cancel] therefore release the active one, and
/// [discover] tears the previous one down before starting a new one.
class MdnsDiscoveryService {
  MdnsDiscoveryService({
    this.serviceType = defaultServiceType,
    this.timeout = const Duration(seconds: 8),
  });

  /// Service type published by the gateway.
  static const String defaultServiceType = '_smartfarm._tcp';

  /// Fully qualified service type, used in status messages.
  static const String defaultFqdn = '$defaultServiceType.local.';

  final String serviceType;
  final Duration timeout;

  Discovery? _discovery;
  ServiceListener? _listener;
  Timer? _timeoutTimer;
  Completer<GatewayEndpoint?>? _pending;
  bool _cancelled = false;
  bool _disposed = false;

  /// Whether a native discovery is currently running.
  bool get isDiscovering => _discovery != null;

  /// Browses for the gateway and completes with the first usable endpoint.
  ///
  /// Returns `null` when the [timeout] elapses, when [cancel] or [dispose] is
  /// called while scanning, or when the service advertises nothing connectable.
  /// Throws [DiscoveryFailure] when discovery fails for a reason the user can
  /// act on, such as a withheld network permission.
  Future<GatewayEndpoint?> discover() async {
    if (_disposed) {
      throw const DiscoveryFailure('Discovery has already been disposed.');
    }

    _cancelled = false;
    _timeoutTimer?.cancel();

    // Supersede a call that is still in flight. Without this its completer
    // loses both its listener and its timer when this call replaces them, so it
    // would await forever and leave the caller suspended.
    final Completer<GatewayEndpoint?>? previous = _pending;
    if (previous != null && !previous.isCompleted) previous.complete(null);

    // Never stack discoveries; a leftover one would eat into Android's NSD
    // operation budget and eventually fail every scan with `maxLimit`.
    await _stopActive();
    if (_cancelled) return null;

    final Completer<GatewayEndpoint?> completer =
        Completer<GatewayEndpoint?>();
    _pending = completer;

    // Cleanup below is scoped to the resources this call created, so a call that
    // has been superseded cannot tear down the discovery that replaced it.
    Discovery? own;
    Timer? ownTimer;

    try {
      own = await startDiscovery(serviceType);
      if (_cancelled) return null;
      _discovery = own;

      void listener(Service service, ServiceStatus status) {
        if (_cancelled) return;
        if (status != ServiceStatus.found) {
          // A lost service is a socket concern, not a discovery concern; the
          // browse stays open so a returning gateway is picked up again.
          return;
        }
        final GatewayEndpoint? endpoint = _endpointFrom(service);
        if (endpoint != null && !completer.isCompleted) {
          completer.complete(endpoint);
        }
      }

      own.addServiceListener(listener);
      _listener = listener;

      // Android only replays services discovered before a listener attaches, so
      // check the snapshot explicitly before waiting for an event.
      for (final Service service in own.services) {
        final GatewayEndpoint? endpoint = _endpointFrom(service);
        if (endpoint != null) {
          if (!completer.isCompleted) completer.complete(endpoint);
          break;
        }
      }

      ownTimer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      return await completer.future;
    } on Object catch (error) {
      if (error is DiscoveryFailure) rethrow;
      throw DiscoveryFailure(_describeError(error));
    } finally {
      if (identical(_pending, completer)) _pending = null;
      ownTimer?.cancel();

      final Discovery? discovery = own;
      if (discovery != null) {
        // Only clear shared state if this call still owns it.
        if (identical(_discovery, discovery)) {
          _discovery = null;
          _listener = null;
        }
        await _stopOne(discovery);
      }
    }
  }

  /// Extracts a connectable endpoint from a resolved mDNS service.
  ///
  /// The lookup order is deliberately not "use whatever came back".
  /// `nsd_android` reports `service.addresses`, but `nsd_windows` never does —
  /// it returns only the SRV target name from `DnsServiceResolve`. Because
  /// `gateway.py` advertises `server="smartfarm.local."`, that name is all that
  /// arrives, and `getaddrinfo` on Windows cannot resolve a `.local` name at
  /// all, so dialling it fails with `WSAHOST_NOT_FOUND` (11001, "No such host is
  /// known"). Therefore:
  ///
  ///  1. an address advertised in the TXT record, which needs no DNS lookup and
  ///     behaves identically on every platform;
  ///  2. an address literal reported in `service.addresses`;
  ///  3. the advertised name, accepted last and flagged as fragile.
  GatewayEndpoint? _endpointFrom(Service service) {
    final int? port = service.port;
    if (port == null || port <= 0) return null;

    final String host = (service.host ?? '').trim();
    final List<String> candidates = <String>[
      ...?service.addresses?.map((e) => e.address),
      if (host.isNotEmpty) host,
    ].where((e) => e.trim().isNotEmpty).toList(growable: false);

    // 1. The gateway can publish its own address in the TXT record. On Windows
    // this is the only source of a verified address.
    final String? advertised = _addressFromTxt(service.txt);
    if (advertised != null) {
      return _endpoint(advertised, port, service, candidates);
    }

    // 2. An address literal the resolver reported directly. IPv4 wins, and
    // IPv6 link-local is skipped because it needs a scope id the record lacks.
    final String? ipv4 = _firstLiteral(candidates, ipv4: true, linkLocal: false);
    if (ipv4 != null) return _endpoint(ipv4, port, service, candidates);

    final String? ipv6 =
        _firstLiteral(candidates, ipv4: false, linkLocal: false);
    if (ipv6 != null) return _endpoint(ipv6, port, service, candidates);

    // 3. Nothing verified; fall back to the advertised name. Loopback targets
    // are never the gateway.
    if (host.isEmpty || host == 'localhost' || host.startsWith('127.')) {
      return null;
    }
    return _endpoint(
      host.endsWith('.') ? host.substring(0, host.length - 1) : host,
      port,
      service,
      candidates,
      fromHostname: true,
    );
  }

  /// Reads an IPv4/IPv6 literal out of the service's TXT record.
  ///
  /// `gateway.py` can advertise `ip=192.168.8.74`. Keys are matched
  /// case-insensitively and a trailing `:port` is tolerated.
  static String? _addressFromTxt(Map<String, List<int>?>? txt) {
    if (txt == null || txt.isEmpty) return null;

    for (final String key in <String>['ip', 'address', 'host']) {
      final List<int>? value = txt[key] ?? txt[key.toUpperCase()];
      if (value == null || value.isEmpty) continue;

      String decoded;
      try {
        decoded = utf8.decode(value).trim();
      } on FormatException {
        continue;
      }

      final int colon = decoded.lastIndexOf(':');
      if (colon > 0 && int.tryParse(decoded.substring(colon + 1)) != null) {
        decoded = decoded.substring(0, colon);
      }

      final String? literal = asIpLiteral(decoded);
      if (literal != null) return literal;
    }
    return null;
  }

  /// Exposed for tests: reads an address literal from a TXT record.
  @visibleForTesting
  static String? addressFromTxtForTest(Map<String, List<int>?>? txt) =>
      _addressFromTxt(txt);

  /// Returns the first address literal matching the requested family, skipping
  /// IPv6 link-local addresses.
  static String? _firstLiteral(
    List<String> candidates, {
    required bool ipv4,
    required bool linkLocal,
  }) {
    for (final String candidate in candidates) {
      final String? literal = asIpLiteral(candidate);
      if (literal == null) continue;
      final bool candidateIsIpv4 = _isIpv4(literal);
      if (candidateIsIpv4 != ipv4) continue;
      if (!ipv4 && !linkLocal && _isLinkLocal(literal)) continue;
      return literal;
    }
    return null;
  }

  /// Whether an IPv6 literal is link-local.
  static bool _isLinkLocal(String value) {
    final String lower = value.toLowerCase();
    return lower.startsWith('fe8') ||
        lower.startsWith('fe9') ||
        lower.startsWith('fea') ||
        lower.startsWith('feb');
  }

  GatewayEndpoint _endpoint(
    String host,
    int port,
    Service service,
    List<String> candidates, {
    bool fromHostname = false,
  }) {
    return GatewayEndpoint(
      host: host,
      port: port,
      name: service.name,
      addresses: List<String>.unmodifiable(candidates),
      fromHostname: fromHostname,
    );
  }

  /// Whether a literal is IPv4.
  static bool _isIpv4(String value) => !value.contains(':');

  /// Returns the trimmed value when it is a bare IPv4 or IPv6 literal, and
  /// `null` for a hostname.
  static String? asIpLiteral(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    // Bracketed IPv6, as it would appear inside a URI authority.
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final String inner = trimmed.substring(1, trimmed.length - 1);
      return Uri.tryParse('http://[$inner]')?.host == inner ? inner : null;
    }
    if (trimmed.contains(':')) {
      // A bare IPv6 literal. A hostname with a stray port would fail to parse.
      return Uri.tryParse('http://[$trimmed]')?.host;
    }

    final List<String> parts = trimmed.split('.');
    if (parts.length != 4) return null;
    if (parts.any((String p) => int.tryParse(p) == null)) return null;
    if (parts.any((String p) => int.parse(p) < 0 || int.parse(p) > 255)) {
      return null;
    }
    return trimmed;
  }

  /// Aborts an in-flight [discover]. Safe to call when idle.
  Future<void> cancel() async {
    _cancelled = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    final Completer<GatewayEndpoint?>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);

    await _stopActive();
  }

  /// Cancels discovery and releases resources. Unusable afterwards.
  Future<void> dispose() async {
    _disposed = true;
    await cancel();
  }

  /// Stops the active discovery and detaches its listener.
  Future<void> _stopActive() async {
    final ServiceListener? listener = _listener;
    _listener = null;

    final Discovery? discovery = _discovery;
    _discovery = null;

    if (discovery == null) return;
    if (listener != null) discovery.removeServiceListener(listener);
    await _stopOne(discovery);
  }

  Future<void> _stopOne(Discovery discovery) async {
    try {
      await stopDiscovery(discovery);
    } on Object {
      // The native discovery may already be gone; there is nothing to recover.
    }
  }

  /// Turns a platform failure into advice the user can act on.
  String _describeError(Object error) {
    // Flutter web has no nsd implementation at all, and browsers cannot browse
    // mDNS. Say so plainly instead of showing a generic network failure.
    if (error is MissingPluginException) {
      return 'mDNS discovery is not available on this platform '
          '(the web build cannot browse the network). Enter the gateway '
          'address manually to connect.';
    }
    if (error is NsdError) {
      switch (error.cause) {
        case ErrorCause.securityIssue:
          return 'Network access was denied. Allow the app to use the local '
              'network, then scan again.';
        case ErrorCause.operationNotSupported:
          return 'This device does not support mDNS discovery.';
        case ErrorCause.maxLimit:
        case ErrorCause.alreadyActive:
          return 'The network is busy. Wait a moment and scan again.';
        case ErrorCause.illegalArgument:
          return 'The gateway advertises an invalid service type '
              '($serviceType).';
        case ErrorCause.internalError:
          return 'The operating system reported an internal discovery error.';
      }
    }
    return 'Network discovery failed. Confirm the phone and the gateway share '
        'the same Wi-Fi network.';
  }
}