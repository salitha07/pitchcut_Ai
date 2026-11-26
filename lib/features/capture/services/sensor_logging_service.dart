import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorLoggingService {
  SensorLoggingService({
    Stream<AccelerometerEvent> Function()? accelerometerSource,
    Stream<GyroscopeEvent> Function()? gyroscopeSource,
  }) : _accelerometerSource =
           accelerometerSource ??
           (() => accelerometerEventStream(
             samplingPeriod: const Duration(milliseconds: 50),
           )),
       _gyroscopeSource =
           gyroscopeSource ??
           (() => gyroscopeEventStream(
             samplingPeriod: const Duration(milliseconds: 50),
           ));

  final Stream<AccelerometerEvent> Function() _accelerometerSource;

  final Stream<GyroscopeEvent> Function() _gyroscopeSource;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  final Stopwatch _stopwatch = Stopwatch();

  final List<Map<String, dynamic>> _samples = [];

  AccelerometerEvent? _lastAccelerometer;
  GyroscopeEvent? _lastGyroscope;

  bool _isRecording = false;
  int _lastSampleMs = -100;

  bool get isRecording => _isRecording;
  int get sampleCount => _samples.length;

  /// Copy samples without exposing the internal list.
  List<Map<String, dynamic>> get samples => _samples
      .map((sample) => Map<String, dynamic>.from(sample))
      .toList(growable: false);

  // ==========================================
  // START SENSOR RECORDING
  // ==========================================

  Future<void> startRecording() async {
    if (_isRecording) return;

    // Sensor capture is Android-first.
    if (kIsWeb) return;

    // Remove subscriptions left by any earlier session.
    await _cancelSubscriptions();

    _samples.clear();
    _lastAccelerometer = null;
    _lastGyroscope = null;
    _lastSampleMs = -100;

    _stopwatch
      ..reset()
      ..start();

    _isRecording = true;

    try {
      _accelerometerSubscription = _accelerometerSource().listen(
        (event) {
          _lastAccelerometer = event;
          _addSample();
        },
        onError: (Object error) {
          debugPrint('Accelerometer error: $error');
          _lastAccelerometer = null;
        },
        cancelOnError: true,
      );

      _gyroscopeSubscription = _gyroscopeSource().listen(
        (event) {
          _lastGyroscope = event;
          _addSample();
        },
        onError: (Object error) {
          debugPrint('Gyroscope error: $error');
          _lastGyroscope = null;
        },
        cancelOnError: true,
      );
    } catch (_) {
      await stopRecording();
      rethrow;
    }
  }

  // ==========================================
  // COLLECT REAL SENSOR SAMPLES
  // ==========================================

  void _addSample() {
    if (!_isRecording) return;

    final accelerometer = _lastAccelerometer;
    final gyroscope = _lastGyroscope;

    // Never invent values for unavailable sensors.
    if (accelerometer == null || gyroscope == null) {
      return;
    }

    final elapsedMs = _stopwatch.elapsedMilliseconds;

    // Target approximately 10 samples per second.
    if (elapsedMs - _lastSampleMs < 100) {
      return;
    }

    final sample = <String, dynamic>{
      'tMs': elapsedMs,
      'ax': accelerometer.x,
      'ay': accelerometer.y,
      'az': accelerometer.z,
      'gx': gyroscope.x,
      'gy': gyroscope.y,
      'gz': gyroscope.z,
    };

    // Ignore malformed or non-finite sensor readings.
    if (!isValidSample(sample)) {
      debugPrint('Skipped an invalid motion sensor sample.');
      return;
    }

    _lastSampleMs = elapsedMs;
    _samples.add(sample);
  }

  // ==========================================
  // STOP SENSOR RECORDING
  // ==========================================

  Future<List<Map<String, dynamic>>> stopRecording() async {
    _isRecording = false;
    _stopwatch.stop();

    await _cancelSubscriptions();

    return samples;
  }

  Future<void> _cancelSubscriptions() async {
    final accelerometer = _accelerometerSubscription;
    final gyroscope = _gyroscopeSubscription;

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;

    await accelerometer?.cancel();
    await gyroscope?.cancel();
  }

  // ==========================================
  // VALIDATE A SINGLE SENSOR SAMPLE
  // ==========================================

  static bool isValidSample(Map<String, dynamic> sample) {
    const requiredKeys = {'tMs', 'ax', 'ay', 'az', 'gx', 'gy', 'gz'};

    if (sample.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(sample.keys.toSet()).isNotEmpty) {
      return false;
    }

    final timestamp = sample['tMs'];

    if (timestamp is! int || timestamp < 0) {
      return false;
    }

    for (final key in ['ax', 'ay', 'az', 'gx', 'gy', 'gz']) {
      final value = sample[key];

      if (value is! num || !value.isFinite) {
        return false;
      }
    }

    return true;
  }

  // ==========================================
  // VALIDATE ALL SENSOR SAMPLES
  // ==========================================

  static bool validateSamples(List<Map<String, dynamic>> samples) {
    if (samples.isEmpty) {
      return false;
    }

    int? previousTimestamp;

    for (final sample in samples) {
      if (!isValidSample(sample)) {
        return false;
      }

      final timestamp = sample['tMs'] as int;

      if (previousTimestamp != null && timestamp <= previousTimestamp) {
        return false;
      }

      previousTimestamp = timestamp;
    }

    return true;
  }

  // ==========================================
  // SAVE SENSOR JSON FILE
  // ==========================================

  Future<String?> saveSensorData({
    required String projectId,
    required String clipId,
  }) async {
    if (kIsWeb || _samples.isEmpty) {
      return null;
    }

    if (_isRecording) {
      throw StateError('Stop sensor recording before saving its data.');
    }

    // IDs form a directory/file path.
    // Accept UUID-style IDs only.
    final idPattern = RegExp(r'^[a-zA-Z0-9-]+$');

    if (!idPattern.hasMatch(projectId) || !idPattern.hasMatch(clipId)) {
      throw ArgumentError('Invalid project or clip ID.');
    }

    if (!validateSamples(_samples)) {
      throw const FormatException('Sensor samples failed validation.');
    }

    final appDirectory = await getApplicationDocumentsDirectory();

    final directory = Directory(p.join(appDirectory.path, 'videos', projectId));

    await directory.create(recursive: true);

    final finalFile = File(p.join(directory.path, '${clipId}_sensors.json'));

    final temporaryFile = File('${finalFile.path}.tmp');

    if (await finalFile.exists()) {
      throw StateError('Sensor data file already exists for this clip.');
    }

    try {
      final jsonContent = jsonEncode(_samples);

      // Write the complete JSON into a temporary file.
      await temporaryFile.writeAsString(jsonContent, flush: true);

      // Verify the temporary file before renaming it.
      final writtenContent = await temporaryFile.readAsString();

      final decoded = jsonDecode(writtenContent);

      if (decoded is! List) {
        throw const FormatException('Saved sensor JSON is not a list.');
      }

      final savedSamples = <Map<String, dynamic>>[];

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid sensor JSON sample.');
        }

        savedSamples.add(item);
      }

      if (!validateSamples(savedSamples) ||
          savedSamples.length != _samples.length) {
        throw const FormatException('Saved sensor JSON failed validation.');
      }

      // Rename only after the complete file is valid.
      final savedFile = await temporaryFile.rename(finalFile.path);

      return savedFile.absolute.path;
    } catch (_) {
      try {
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } catch (cleanupError) {
        debugPrint(
          'Unable to delete temporary sensor file: '
          '$cleanupError',
        );
      }

      rethrow;
    }
  }

  // ==========================================
  // CLEANUP
  // ==========================================

  Future<void> dispose() async {
    await stopRecording();
  }
}
