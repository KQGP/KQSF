import 'package:flutter/material.dart';

import 'state/farm_controller.dart';
import 'theme/app_theme.dart';
import 'views/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartFarmApp());
}

/// Root widget.
///
/// Owns the single [FarmController] and rebuilds only when it has something new
/// to say, so the connection, telemetry and theme choices live for the whole
/// session rather than for one screen.
class SmartFarmApp extends StatefulWidget {
  const SmartFarmApp({super.key, this.controller});

  /// Injectable for tests; the app creates its own when omitted.
  final FarmController? controller;

  @override
  State<SmartFarmApp> createState() => _SmartFarmAppState();
}

class _SmartFarmAppState extends State<SmartFarmApp> {
  /// True when this widget created the controller and is therefore the one
  /// that has to tear it down. An injected controller belongs to its caller.
  late final bool _ownsController = widget.controller == null;

  late final FarmController _controller =
      widget.controller ?? FarmController();

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: 'Smart Farm',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _controller.themeMode,
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}