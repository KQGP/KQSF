import 'farm_telemetry.dart';

/// A fixed-capacity ring buffer of recent readings for one channel.
///
/// The board broadcasts once a second, so a 90-sample window covers the last
/// minute and a half of the farm. Storing samples in a ring rather than a
/// growing list keeps the dashboard's memory flat no matter how long it is left
/// open, which matters for a display that may sit on a wall for days.
class ReadingSeries {
  ReadingSeries({this.capacity = 90})
      : _buffer = List<double?>.filled(capacity, null);

  /// How many samples are retained; older ones are overwritten.
  final int capacity;

  /// Fixed-size backing store. Slots are filled in circular order.
  final List<double?> _buffer;

  /// Index of the oldest retained sample.
  int _start = 0;

  /// How many slots hold a sample, up to [capacity].
  int _count = 0;

  /// Number of retained samples.
  int get length => _count;

  /// Whether no sample has been recorded yet.
  bool get isEmpty => _count == 0;

  /// Appends [value], overwriting the oldest sample once full.
  void add(double value) {
    if (_count < capacity) {
      _buffer[(_start + _count) % capacity] = value;
      _count++;
    } else {
      _buffer[_start] = value;
      _start = (_start + 1) % capacity;
    }
  }

  /// The retained samples, oldest first.
  List<double> get samples {
    if (_count == 0) return const <double>[];
    return <double>[
      for (int i = 0; i < _count; i++) _buffer[(_start + i) % capacity]!,
    ];
  }

  /// The most recent sample, or `null` before the first frame.
  double? get latest => _count == 0 ? null : _buffer[(_start + _count - 1) % capacity];

  /// Smallest retained sample.
  double? get minimum => _reduce((double a, double b) => a < b ? a : b);

  /// Largest retained sample.
  double? get maximum => _reduce((double a, double b) => a > b ? a : b);

  /// Drops every sample, used when the link drops so a stale trend is never
  /// shown next to a fresh reading.
  void clear() {
    for (int i = 0; i < capacity; i++) {
      _buffer[i] = null;
    }
    _start = 0;
    _count = 0;
  }

  double? _reduce(double Function(double, double) combine) {
    if (_count == 0) return null;
    final List<double> values = samples;
    double result = values.first;
    for (int i = 1; i < values.length; i++) {
      result = combine(result, values[i]);
    }
    return result;
  }
}

/// Recent readings for every channel the dashboard charts.
///
/// Kept separate from [FarmTelemetry] because a telemetry value is a single
/// instantaneous reading, whereas this is a rolling window used for trends.
class TelemetryHistory {
  TelemetryHistory({this.windowSize = 90})
      : soil = ReadingSeries(capacity: windowSize),
        rain = ReadingSeries(capacity: windowSize),
        temp = ReadingSeries(capacity: windowSize),
        hum = ReadingSeries(capacity: windowSize);

  /// Samples retained per channel, i.e. the length of the trend window.
  final int windowSize;

  final ReadingSeries soil;
  final ReadingSeries rain;
  final ReadingSeries temp;
  final ReadingSeries hum;

  /// Records one telemetry frame against every channel.
  void add(FarmTelemetry frame) {
    soil.add(frame.soil.toDouble());
    rain.add(frame.rain.toDouble());
    temp.add(frame.temp);
    hum.add(frame.hum);
  }

  /// Empties every channel.
  void clear() {
    soil.clear();
    rain.clear();
    temp.clear();
    hum.clear();
  }

  /// Whether any channel has enough data to draw a trend.
  bool get hasTrend => soil.length > 1;

  /// Human-readable span covered by [windowSize] samples, given the board's
  /// one-second broadcast interval.
  String get windowLabel => windowSize >= 90
      ? 'last ${(windowSize / 60).round()} min'
      : 'last $windowSize s';
}