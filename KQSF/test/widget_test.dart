// Smoke, protocol and widget tests for the Smart Farm dashboard.
//
// The widgets are exercised without a live gateway: the controller is built
// with `autoConnect: false` so nothing is dialled, the tree still builds, and
// every control stays disabled.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/main.dart';
import 'package:smart_farm/models/farm_telemetry.dart';
import 'package:smart_farm/models/telemetry_history.dart';
import 'package:smart_farm/services/websocket_service.dart';
import 'package:smart_farm/state/farm_controller.dart';
import 'package:smart_farm/theme/farm_palette.dart';
import 'package:smart_farm/views/app_shell.dart';
import 'package:smart_farm/views/widgets/connection_bar.dart';
import 'package:smart_farm/views/widgets/gauge_ring.dart';
import 'package:smart_farm/views/widgets/pump_control_card.dart';
import 'package:smart_farm/views/widgets/roof_control_card.dart';
import 'package:smart_farm/views/widgets/sensor_card.dart';
import 'package:smart_farm/views/widgets/sparkline.dart';

void main() {
  group('FarmTelemetry', () {
    test('parses a full firmware frame', () {
      final FarmTelemetry telemetry = FarmTelemetry.fromJson(<String, dynamic>{
        'soil': 412,
        'rain': 180,
        'temp': 26.4,
        'hum': 61.0,
        'p1_auto': true,
        'p1_state': true,
        'p2_state': false,
        'servo_auto': false,
        'servo_angle': 135,
      });

      expect(telemetry.soil, 412);
      expect(telemetry.rain, 180);
      expect(telemetry.temp, closeTo(26.4, 1e-9));
      expect(telemetry.hum, closeTo(61.0, 1e-9));
      expect(telemetry.p1Auto, isTrue);
      expect(telemetry.p1State, isTrue);
      expect(telemetry.p2State, isFalse);
      expect(telemetry.servoAngle, closeTo(135, 1e-9));
    });

    test('falls back to firmware power-on defaults for missing keys', () {
      final FarmTelemetry telemetry =
          FarmTelemetry.fromJson(<String, dynamic>{'soil': 500, 'temp': 21.5});

      expect(telemetry.soil, 500);
      expect(telemetry.temp, closeTo(21.5, 1e-9));
      expect(telemetry.rain, 0);
      expect(telemetry.p1Auto, isTrue);
      expect(telemetry.p1State, isFalse);
      expect(telemetry.p2State, isFalse);
      expect(telemetry.servoAuto, isTrue);
      expect(telemetry.servoAngle, FarmTelemetry.defaultServoAngle);
    });

    test('survives null, string and non-finite values', () {
      final FarmTelemetry telemetry = FarmTelemetry.fromJson(<String, dynamic>{
        'soil': null,
        'rain': '180',
        'temp': double.nan,
        'hum': '61.5',
        'p1_auto': 'false',
        'servo_angle': '180',
      });

      expect(telemetry.soil, 0);
      expect(telemetry.rain, 180);
      expect(telemetry.temp, 0.0);
      expect(telemetry.hum, closeTo(61.5, 1e-9));
      expect(telemetry.p1Auto, isFalse);
      expect(telemetry.servoAngle, closeTo(180, 1e-9));
    });

    test('classifies readings with the firmware thresholds', () {
      FarmTelemetry at(int soil, int rain) =>
          FarmTelemetry.fromJson(<String, dynamic>{'soil': soil, 'rain': rain});

      // The board starts irrigation below 600 and opens the roof at 300.
      expect(at(599, 0).isSoilDry, isTrue);
      expect(at(600, 0).isSoilDry, isFalse);
      expect(at(0, 299).isRaining, isFalse);
      expect(at(0, 300).isRaining, isTrue);
    });

    test('serialises servo_angle as a clamped integer', () {
      // Manual travel is 90-180, so anything outside that is clamped.
      final FarmTelemetry telemetry = FarmTelemetry(servoAngle: 200.6);

      expect(telemetry.toJson()['servo_angle'], 180);
      expect(
        FarmTelemetry.fromJson(<String, dynamic>{'servo_angle': -5})
            .toJson()['servo_angle'],
        90,
      );
    });

    test('parses the firmware default of 90 degrees', () {
      final FarmTelemetry telemetry =
          FarmTelemetry.fromJson(<String, dynamic>{});
      expect(telemetry.servoAngle, 90);
      expect(telemetry.servoAngleDegrees, 90);
    });

    test('the manual travel range matches the firmware', () {
      // Mirrors SERVO_REST_ANGLE / SERVO_OPEN_ANGLE / SERVO_RAIN_ANGLE in
      // smart_farm.ino.
      expect(FarmTelemetry.servoMinAngle, 90);
      expect(FarmTelemetry.servoMaxAngle, 180);
      expect(FarmTelemetry.defaultServoAngle, 90);
    });

    test('builds command payloads the firmware accepts', () {
      expect(FarmTelemetry.pump1AutoCommand(false),
          <String, dynamic>{'p1_auto': false});

      expect(
        FarmTelemetry.pump1Command(auto: false, state: true),
        <String, dynamic>{'p1_auto': false, 'p1_state': true},
      );
      expect(
        FarmTelemetry.pump2Command(false),
        <String, dynamic>{'p2_state': false},
      );
      expect(
        FarmTelemetry.pump2Command(true),
        <String, dynamic>{'p2_state': true},
      );
      // Within the usable 90-180 travel the angle is sent as sent.
      expect(
        FarmTelemetry.servoCommand(auto: false, angle: 133.7),
        <String, dynamic>{'servo_auto': false, 'servo_angle': 134},
      );
      // Sent out of range, the board would clamp anyway; clamp here instead.
      expect(
        FarmTelemetry.servoCommand(auto: false, angle: 999),
        <String, dynamic>{'servo_auto': false, 'servo_angle': 180},
      );
      // Below the closed end clamps up to 90, never below.
      expect(
        FarmTelemetry.servoCommand(auto: false, angle: 0),
        <String, dynamic>{'servo_auto': false, 'servo_angle': 90},
      );
    });
  });

  group('FarmSocketService', () {
    test('recovers every complete frame from a coalesced payload', () {
      // Two documents plus the debris a partial serial read can leave behind.
      const String payload = '{"soil":1}{"soil":2}{"so';
      final List<String> documents = FarmSocketService.splitJsonDocuments(payload);

      expect(documents.length, 2);
      expect(documents.first, '{"soil":1}');
      expect(documents.last, '{"soil":2}');
    });

    test('is not confused by braces inside string values', () {
      const String payload = '{"note":"a } brace {"}';
      expect(FarmSocketService.splitJsonDocuments(payload), <String>[payload]);
    });
  });

  group('TelemetryHistory', () {
    test('reports min, max and latest across the window', () {
      final TelemetryHistory history = TelemetryHistory(windowSize: 4);
      for (final double v in <double>[3, 1, 4, 2]) {
        history.temp.add(v);
      }

      expect(history.temp.samples, <double>[3, 1, 4, 2]);
      expect(history.temp.minimum, 1);
      expect(history.temp.maximum, 4);
      expect(history.temp.latest, 2);
      expect(history.windowLabel, 'last 4 s');
    });

    test('keeps memory flat by overwriting the oldest sample', () {
      final ReadingSeries series = ReadingSeries(capacity: 3);
      for (final double v in <double>[1, 2, 3, 4, 5]) {
        series.add(v);
      }

      expect(series.length, 3);
      // Still exactly the newest three, in order.
      expect(series.samples, <double>[3, 4, 5]);
    });

    test('clear drops every sample so a stale trend is never redrawn', () {
      final TelemetryHistory history = TelemetryHistory();
      history.add(const FarmTelemetry(soil: 400, temp: 20));
      expect(history.hasTrend, isFalse);

      history.add(const FarmTelemetry(soil: 300, temp: 21));
      expect(history.hasTrend, isTrue);

      history.clear();
      expect(history.hasTrend, isFalse);
      expect(history.soil.latest, isNull);
      expect(history.temp.maximum, isNull);
    });

    test('records every channel from one frame', () {
      final TelemetryHistory history = TelemetryHistory();
      history.add(const FarmTelemetry(soil: 412, rain: 180, temp: 26.4, hum: 61));

      expect(history.soil.latest, 412);
      expect(history.rain.latest, 180);
      expect(history.temp.latest, closeTo(26.4, 1e-9));
      expect(history.hum.latest, closeTo(61, 1e-9));
    });
  });

  group('FarmPalette', () {
    test('light and dark define every token, and lerp produces one', () {
      final FarmPalette light = FarmPalette.light();
      final FarmPalette dark = FarmPalette.dark();

      // Every token must actually change with the theme; a light value left
      // behind in the dark palette is the classic way a dark theme ends up
      // with an unreadable card.
      expect(light.canvas, isNot(dark.canvas));
      expect(light.surface, isNot(dark.surface));
      expect(light.ink, isNot(dark.ink));
      expect(light.inkSoft, isNot(dark.inkSoft));
      expect(light.inkFaint, isNot(dark.inkFaint));
      expect(light.soil, isNot(dark.soil));
      expect(light.online, isNot(dark.online));

      // Interpolating between the two is what makes the theme switch animate
      // rather than snap, so every channel has to accept it.
      final FarmPalette middle = light.lerp(dark, 0.5);
      expect(middle.canvas, isNot(light.canvas));
      expect(middle.canvas, isNot(dark.canvas));
      // Lerping towards nothing returns the receiver untouched, which is what
      // lets the theme interpolate without a second palette to blend against.
      expect(middle.lerp(null, 0.5), same(middle));
    });

    test('copyWith replaces only the tokens it is given', () {
      final FarmPalette base = FarmPalette.light();
      final FarmPalette changed = base.copyWith(danger: const Color(0xFFFF00FF));

      expect(changed.danger, const Color(0xFFFF00FF));
      expect(changed.canvas, base.canvas);
      expect(changed.soil, base.soil);
    });
  });

  group('FarmController', () {
    test('starts idle and reports no reading', () {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      expect(controller.isOnline, isFalse);
      expect(controller.isBusy, isFalse);
      expect(controller.hasReading, isFalse);
      expect(controller.history.hasTrend, isFalse);
    });

    test('switching to the dark theme and back flips the mode', () {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      expect(controller.themeMode, ThemeMode.system);

      controller.toggleTheme(Brightness.light);
      expect(controller.themeMode, ThemeMode.dark);

      // Already dark, so the next tap has to go back the other way.
      controller.toggleTheme(Brightness.dark);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('selectTab moves between the two tabs and ignores bad input', () {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      controller.selectTab(1);
      expect(controller.tabIndex, 1);

      controller.selectTab(1);
      expect(controller.tabIndex, 1, reason: 're-selecting is a no-op');

      controller.selectTab(7);
      expect(controller.tabIndex, 1, reason: 'out-of-range index is ignored');
    });
  });

  group('widgets', () {
    testWidgets('SensorCard renders value, unit, state and caption', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SensorCard(
              label: 'Soil moisture',
              valueText: '412',
              unitText: '/ 1023',
              icon: Icons.grass_rounded,
              color: FarmPalette.light().soil,
              fraction: 0.4,
              threshold: 0.58,
              stateLabel: 'Wet',
              stateColor: FarmPalette.light().soil,
              scaleLabel: 'Board waters below 600',
              trend: <double>[390, 401, 380, 412],
              trendFormat: (double v) => v.toStringAsFixed(0),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Soil moisture'), findsOneWidget);
      expect(
        find.widgetWithText(GaugeRing, '412'),
        findsOneWidget,
        reason: 'the reading sits inside the ring gauge',
      );
      expect(find.text('/ 1023'), findsOneWidget);
      expect(find.text('WET'), findsOneWidget);
      expect(find.text('Board waters below 600'), findsOneWidget);
      // The min/max caption under the trend, but not the window span: that is
      // stated once by the section heading above the grid.
      expect(find.text('380'), findsOneWidget);
      expect(find.text('412'), findsNWidgets(2));
      expect(find.byType(GaugeRing), findsOneWidget);
    });

    testWidgets('SensorCard shows a dash before the first frame arrives', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SensorCard(
              label: 'Humidity',
              valueText: '—',
              unitText: '%',
              icon: Icons.water_rounded,
              color: FarmPalette.light().humidity,
              fraction: 0,
              stateLabel: 'Stale',
              stateColor: FarmPalette.light().inkFaint,
              hasReading: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('STALE'), findsOneWidget);
    });

    testWidgets('Sparkline copes with too little data to draw a trend', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: Column(
                  children: <Widget>[
                    Sparkline(
                      values: const <double>[],
                      color: FarmPalette.light().soil,
                    ),
                    Sparkline(
                      values: const <double>[7],
                      color: FarmPalette.light().soil,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('GaugeRing paints at any fraction, including a frozen one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                GaugeRing(value: 0.42, color: Colors.green, child: const Text('a')),
                GaugeRing(value: 1.4, color: Colors.blue, child: const Text('b')),
                GaugeRing(
                  value: double.nan,
                  color: Colors.red,
                  threshold: 0.5,
                  child: const Text('c'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('PumpControlCard hides the power button in auto mode', (
      WidgetTester tester,
    ) async {
      final List<bool> manualStates = <bool>[];

      Widget build({required bool autoMode}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PumpControlCard(
              title: 'Pump 1',
              subtitle: 'Irrigation',
              autoMode: autoMode,
              isRunning: false,
              enabled: true,
              onAutoModeChanged: (bool value) {},
              onRunStateChanged: manualStates.add,
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(autoMode: true));
      await tester.pump();

      expect(find.text('Pump 1'), findsOneWidget);
      expect(find.text('Board controlled'), findsOneWidget);
      expect(find.text('OFF'), findsNothing);
      expect(find.text('ON'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('pump-power-Pump 1')),
        findsNothing,
      );

      await tester.pumpWidget(build(autoMode: false));
      await tester.pump();

      // The relay reads Off in the badge and on the power control.
      expect(find.text('OFF'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey<String>('pump-power-Pump 1')));
      await tester.pump();
      expect(manualStates, <bool>[true]);
    });

    testWidgets('a running pump reports itself as running', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PumpControlCard(
                title: 'Pump 1',
                subtitle: 'Irrigation',
                autoMode: true,
                isRunning: true,
                enabled: true,
                runningLabel: 'Watering',
                onAutoModeChanged: (bool value) {},
                onRunStateChanged: (bool value) {},
              ),
            ),
          ),
        ),
      );
      // The running badge breathes, so the tree is never "settled"; pump a fixed
      // span instead.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('WATERING'), findsOneWidget);
      expect(find.text('Board controlled'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('pump-power-Pump 1')),
        findsNothing,
      );
    });

    testWidgets('manualOnly hides the switch and keeps the control', (
      WidgetTester tester,
    ) async {
      final List<bool> manualStates = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PumpControlCard(
                title: 'Pump 2',
                subtitle: 'Auxiliary',
                // Even if the board reports auto mode on, a pump with no
                // automatic rule must not offer the switch.
                autoMode: true,
                isRunning: false,
                enabled: true,
                manualOnly: true,
                onAutoModeChanged: (bool value) {},
                onRunStateChanged: manualStates.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Switch), findsNothing);
      expect(find.text('Board controlled'), findsNothing);
      expect(find.text('OFF'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey<String>('pump-power-Pump 2')));
      await tester.pump();
      expect(manualStates, <bool>[true]);
    });

    testWidgets('the auto switch reports the requested mode', (
      WidgetTester tester,
    ) async {
      final List<bool> modes = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PumpControlCard(
                title: 'Pump 1',
                subtitle: 'Irrigation',
                autoMode: false,
                isRunning: false,
                enabled: true,
                onAutoModeChanged: modes.add,
                onRunStateChanged: (bool value) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(modes, <bool>[true]);
    });

    testWidgets('a disabled pump cannot be driven', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PumpControlCard(
                title: 'Pump 1',
                subtitle: 'Irrigation',
                autoMode: false,
                isRunning: false,
                enabled: false,
                onAutoModeChanged: (bool value) {},
                onRunStateChanged: (bool value) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Both the mode switch and the power control are inert while offline.
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets('RoofControlCard exposes presets only in manual mode', (
      WidgetTester tester,
    ) async {
      final List<int> angles = <int>[];

      Widget build({required bool autoMode}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoofControlCard(
              autoMode: autoMode,
              angle: 90,
              enabled: true,
              onAutoModeChanged: (bool value) {},
              onAngleChanged: angles.add,
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(autoMode: true));
      await tester.pump();

      expect(find.byType(Slider), findsNothing);
      expect(find.text('Closed'), findsNothing);

      await tester.pumpWidget(build(autoMode: false));
      // The card grows its manual section with AnimatedSize; tapping mid
      // animation would hit a clipped widget.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(Slider), findsOneWidget);
      // The two presets read as a pair: the cover closes at 90 and opens to
      // 180; 0 is firmware-internal and has no control.
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Close'), findsNothing);
      expect(find.text('Half'), findsNothing);

      // The slider spans the cover's usable travel only.
      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 90);
      expect(slider.max, 180);
      expect(slider.value, greaterThanOrEqualTo(90));
      expect(slider.value, lessThanOrEqualTo(180));

      await tester.tap(find.byKey(const ValueKey<String>('servo-preset-180')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(angles, <int>[180]);

      await tester.tap(find.byKey(const ValueKey<String>('servo-preset-90')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(angles, <int>[180, 90]);
    });

    testWidgets('the roof auto switch is reachable from manual mode', (
      WidgetTester tester,
    ) async {
      final List<bool> modes = <bool>[];

      Widget build({required bool autoMode}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoofControlCard(
              autoMode: autoMode,
              angle: 120,
              enabled: true,
              onAutoModeChanged: modes.add,
              onAngleChanged: (int value) {},
            ),
          ),
        ),
      );

      // The switch has to be there in manual mode too. Without it the only way
      // back to automatic control would be the board changing the flag itself.
      await tester.pumpWidget(build(autoMode: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('AUTO'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(modes, <bool>[true]);

      // Still there on the way back down, so manual can be re-entered.
      await tester.pumpWidget(build(autoMode: true));
      await tester.pump();
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('the roof diagram and readout follow the angle', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoofControlCard(
                autoMode: true,
                angle: 135,
                enabled: true,
                onAutoModeChanged: (bool value) {},
                onAngleChanged: (int value) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('135°'), findsOneWidget);
      expect(find.text('PART OPEN'), findsOneWidget);
      // The cover position is drawn, not only described.
      expect(find.byType(RoofDial), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('app', () {
    testWidgets('boots to the shell with both tabs available', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Smart Farm'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Controls'), findsOneWidget);

      // The dashboard is the landing page and shows the link status plus the
      // four sensor channels.
      expect(find.text('Live'), findsNothing);
      expect(find.text('Greenhouse sensors'), findsOneWidget);
      expect(find.text('Soil moisture'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
    });

    testWidgets('the gateway action lives in the app bar, not the status card', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();

      // One place opens the gateway sheet. A second copy inside the status
      // card made the connection look like it had two separate settings.
      expect(find.byTooltip('Gateway address'), findsOneWidget);
      expect(find.byType(ConnectionBar), findsOneWidget);
      // The status card keeps the one action that is genuinely about the link.
      expect(find.byTooltip('Scan again'), findsOneWidget);
    });

    testWidgets('switching tabs moves to the controls', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();

      await tester.tap(find.text('Controls'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(controller.tabIndex, 1);
      expect(find.text('Irrigation'), findsOneWidget);
      expect(find.text('Pump 1'), findsOneWidget);
      // Offline, so the controls explain why they are inert.
      expect(
        find.textContaining('Not connected to the gateway'),
        findsOneWidget,
      );

      // The roof control lives further down the page, so scroll it into view
      // before asserting it built.
      await tester.scrollUntilVisible(
        find.text('Roof servos'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Roof servos'), findsOneWidget);
    });

    testWidgets('the theme toggle switches the whole app', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();

      expect(
        Theme.of(tester.element(find.byType(AppShell))).brightness,
        Brightness.light,
      );

      await tester.tap(find.byTooltip('Switch to dark'));
      await tester.pump();
      expect(controller.themeMode, ThemeMode.dark);

      // MaterialApp cross-fades between the two themes rather than snapping,
      // so the app is only fully dark once the transition has run.
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        Theme.of(tester.element(find.byType(AppShell))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('a wide window swaps the bar for a rail without losing the tab', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      // Start wide enough to get the rail.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.text('Controls'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Irrigation'), findsOneWidget);

      // Resize across the breakpoint. The navigation changes shape, but the
      // selected tab must survive it: the page view is the same element before
      // and after, so it must not quietly snap back to the dashboard.
      tester.view.physicalSize = const Size(700, 1000);
      await tester.pump();
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(controller.tabIndex, 1);
      expect(
        find.text('Irrigation'),
        findsOneWidget,
        reason: 'the visible page must match the selected tab after a resize',
      );
    });

    testWidgets('the dashboard lays out without overflow on a wide window', (
      WidgetTester tester,
    ) async {
      final FarmController controller = FarmController(autoConnect: false);
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(SmartFarmApp(controller: controller));
      await tester.pump();

      // A wide window shows all four sensor cards across.
      expect(find.byType(SensorCard), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });
}