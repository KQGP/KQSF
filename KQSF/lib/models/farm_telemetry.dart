/// Immutable snapshot of a single telemetry frame broadcast by the farm
/// gateway (`gateway.py`), which mirrors the JSON produced by the firmware
/// (`smart_farm.ino`).
///
/// Wire format (device -> app), one JSON object per second:
///
/// ```json
/// {"soil":412,"rain":180,"temp":26.4,"hum":61.0,
///  "p1_auto":true,"p1_state":false,
///  "p2_state":false,
///  "servo_auto":true,"servo_angle":90}
/// ```
///
/// Wire format (app -> device) accepts the same keys as commands; see the
/// `*Command` constructors below. The firmware only reads the control keys and
/// ignores anything else.
class FarmTelemetry {
  const FarmTelemetry({
    this.soil = 0,
    this.rain = 0,
    this.temp = 0.0,
    this.hum = 0.0,
    this.p1Auto = true,
    this.p1State = false,
    this.p2State = false,
    this.servoAuto = true,
    this.servoAngle = defaultServoAngle,
  });

  /// Builds a snapshot from a decoded gateway frame.
  ///
  /// Every field falls back to the firmware's power-on default when the key is
  /// missing or unparsable, so a partially populated or malformed frame never
  /// throws and never leaves the UI in an undefined state.
  factory FarmTelemetry.fromJson(Map<String, dynamic> json) {
    return FarmTelemetry(
      soil: _asInt(json['soil'], 0),
      rain: _asInt(json['rain'], 0),
      temp: _asDouble(json['temp'], 0.0),
      hum: _asDouble(json['hum'], 0.0),
      p1Auto: _asBool(json['p1_auto'], true),
      p1State: _asBool(json['p1_state'], false),
      p2State: _asBool(json['p2_state'], false),
      servoAuto: _asBool(json['servo_auto'], true),
      servoAngle: _asDouble(json['servo_angle'], defaultServoAngle),
    );
  }

  /// Returns an empty snapshot, used before the first frame has arrived.
  factory FarmTelemetry.initial() => const FarmTelemetry();

  // ---------------------------------------------------------------------------
  // Firmware constants
  //
  // Mirrored from `smart_farm.ino` so the UI can classify raw readings with
  // exactly the same logic the board uses for its automatic decisions.
  // ---------------------------------------------------------------------------

  /// Below this analog reading the soil probe is considered dry, and this is
  /// what auto mode uses to trigger Pump 1 (`SOIL_THRESHOLD`).
  static const int soilDryThreshold = 600;

  /// At or above this analog reading the rain probe is considered wet, and this
  /// is what auto mode uses to drive the roof servos (`RAIN_THRESHOLD`).
  static const int rainWetThreshold = 300;

  /// Full-scale reading of the 10-bit ADC on the board.
  static const int analogMax = 1023;

  /// Angle the cover rests at with the tent closed, and the lower bound of the
  /// range an operator can command (`servoAngle` in `smart_farm.ino`).
  static const double defaultServoAngle = 90;

  /// Closed / parked position, and the bottom of the manual travel.
  static const double servoMinAngle = 90;

  /// Fully open, and the top of the manual travel.
  static const double servoMaxAngle = 180;

  /// Raw analog reading of the soil moisture probe, 0..[analogMax].
  ///
  /// The probe is capacitive, so a *lower* reading means drier soil.
  final int soil;

  /// Raw analog reading of the rain probe, 0..[analogMax].
  ///
  /// A *higher* reading means wetter conditions.
  final int rain;

  /// Air temperature in degrees Celsius. The firmware substitutes `0.0` when
  /// the DHT11 read fails.
  final double temp;

  /// Relative air humidity in percent. The firmware substitutes `0.0` when the
  /// DHT11 read fails.
  final double hum;

  /// Whether Pump 1 runs under the board's soil-threshold logic.
  final bool p1Auto;

  /// Whether the Pump 1 relay is energised.
  final bool p1State;

  /// Whether the Pump 2 relay is energised.
  ///
  /// Pump 2 has no automatic mode: it is driven by hand from the app or by a
  /// bare 0/1 written to the board, so no mode field is reported.
  final bool p2State;

  /// Whether the roof servos follow the board's rain-threshold logic.
  final bool servoAuto;

  /// Commanded cover angle in degrees.
  ///
  /// Both servos hold the tent together and always move as one, so a single
  /// angle describes them. The board parks the cover at [servoMinAngle] and
  /// opens it to [servoMaxAngle]; that is the range the app can command.
  final double servoAngle;

  // ---------------------------------------------------------------------------
  // Derived readings
  // ---------------------------------------------------------------------------

  /// True when the soil probe reads drier than the firmware's threshold.
  bool get isSoilDry => soil < soilDryThreshold;

  /// True when the rain probe reads wetter than the firmware's threshold.
  bool get isRaining => rain >= rainWetThreshold;

  /// Soil reading expressed as a 0..1 fraction of the ADC range for progress
  /// indicators. Note this is the raw probe scale, not a true volumetric
  /// water content percentage.
  double get soilFraction => (soil / analogMax).clamp(0.0, 1.0);

  /// Rain reading expressed as a 0..1 fraction of the ADC range.
  double get rainFraction => (rain / analogMax).clamp(0.0, 1.0);

  /// Servo angle rounded to the whole degrees the firmware expects.
  int get servoAngleDegrees => servoAngle.round();

  // ---------------------------------------------------------------------------
  // Command generation
  // ---------------------------------------------------------------------------

  /// Serialises the full state back to the wire format.
  ///
  /// `servo_angle` is emitted as an integer because the board reads it into an
  /// `int`, and the angle is clamped to the servo's physical range.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'soil': soil,
      'rain': rain,
      'temp': temp,
      'hum': hum,
      'p1_auto': p1Auto,
      'p1_state': p1State,
      'p2_state': p2State,
      'servo_auto': servoAuto,
      'servo_angle': servoAngleDegrees.clamp(
        servoMinAngle.toInt(),
        servoMaxAngle.toInt(),
      ),
    };
  }

  /// Switches Pump 1 between automatic and manual control.
  ///
  /// Turning automatic mode *on* deliberately sends no `p1_state`: the board
  /// owns the relay from that point, and the firmware ignores `p1_state`
  /// while auto mode is active.
  static Map<String, dynamic> pump1AutoCommand(bool auto) =>
      <String, dynamic>{'p1_auto': auto};

  /// Drives Pump 1 from the app.
  ///
  /// Both keys travel together because the firmware applies `p1_auto` before
  /// it evaluates `p1_state` within the same frame, so a single message always
  /// leaves the relay in the requested state.
  static Map<String, dynamic> pump1Command({required bool auto, bool? state}) =>
      state == null
          ? <String, dynamic>{'p1_auto': auto}
          : <String, dynamic>{'p1_auto': auto, 'p1_state': state};

  /// Drives Pump 2 from the app.
  ///
  /// Only `p2_state` is sent: the board has no mode for this pump, and it
  /// applies the state whenever the key is present.
  static Map<String, dynamic> pump2Command(bool state) =>
      <String, dynamic>{'p2_state': state};

  /// Switches the roof servos between automatic and manual control.
  static Map<String, dynamic> servoAutoCommand(bool auto) =>
      <String, dynamic>{'servo_auto': auto};

  /// Drives the roof servos to [angle] degrees from the app.
  ///
  /// Sent as an integer clamped to 0..180, matching the firmware's `int`.
  static Map<String, dynamic> servoCommand({
    required bool auto,
    required double angle,
  }) {
    final int clamped = angle
        .round()
        .clamp(servoMinAngle.toInt(), servoMaxAngle.toInt());
    return <String, dynamic>{'servo_auto': auto, 'servo_angle': clamped};
  }

  /// Returns a copy with the given fields replaced, used to echo a command
  /// locally until the board confirms it in the next telemetry frame.
  FarmTelemetry copyWith({
    int? soil,
    int? rain,
    double? temp,
    double? hum,
    bool? p1Auto,
    bool? p1State,
    bool? p2State,
    bool? servoAuto,
    double? servoAngle,
  }) {
    return FarmTelemetry(
      soil: soil ?? this.soil,
      rain: rain ?? this.rain,
      temp: temp ?? this.temp,
      hum: hum ?? this.hum,
      p1Auto: p1Auto ?? this.p1Auto,
      p1State: p1State ?? this.p1State,
      p2State: p2State ?? this.p2State,
      servoAuto: servoAuto ?? this.servoAuto,
      servoAngle: servoAngle ?? this.servoAngle,
    );
  }

  @override
  String toString() =>
      'FarmTelemetry(soil: $soil, rain: $rain, temp: $temp, hum: $hum, '
      'p1Auto: $p1Auto, p1State: $p1State, p2State: $p2State, '
      'servoAuto: $servoAuto, servoAngle: $servoAngle)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FarmTelemetry &&
        other.soil == soil &&
        other.rain == rain &&
        other.temp == temp &&
        other.hum == hum &&
        other.p1Auto == p1Auto &&
        other.p1State == p1State &&
        other.p2State == p2State &&
        other.servoAuto == servoAuto &&
        other.servoAngle == servoAngle;
  }

  @override
  int get hashCode => Object.hash(
    soil,
    rain,
    temp,
    hum,
    p1Auto,
    p1State,
    p2State,
    servoAuto,
    servoAngle,
  );

  // ---------------------------------------------------------------------------
  // Lenient coercion
  //
  // The board emits well typed JSON, but a firmware change, a truncated frame
  // or a hand-crafted gateway payload should degrade to a default rather than
  // crash the dashboard.
  // ---------------------------------------------------------------------------

  static int _asInt(Object? value, int fallback) {
    if (value is num) {
      return value.isFinite ? value.round() : fallback;
    }
    if (value is String) {
      final int? parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
      final double? asDouble = double.tryParse(value.trim());
      if (asDouble != null && asDouble.isFinite) return asDouble.round();
    }
    return fallback;
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is num) {
      return value.isFinite ? value.toDouble() : fallback;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return fallback;
  }

  static bool _asBool(Object? value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'on':
        case 'yes':
          return true;
        case 'false':
        case '0':
        case 'off':
        case 'no':
          return false;
      }
    }
    return fallback;
  }
}