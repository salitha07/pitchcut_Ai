import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorLoggingService {
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

  // Start capturing sensors when video recording starts.
  Future<void> startRecording() async {
    if (_isRecording) return;

    if (kIsWeb) {
      // Web sensor capture is not enabled in this
      // Android-first implementation.
      return;
    }

    _samples.clear();
    _lastAccelerometer = null;
    _lastGyroscope = null;
    _lastSampleMs = -100;

    _stopwatch
      ..reset()
      ..start();

    _isRecording = true;

    try {
      _accelerometerSubscription =
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 50),
          ).listen(
            (event) {
              _lastAccelerometer = event;
              _addSample();
            },
            onError: (Object error) {
              debugPrint('Accelerometer error: $error');
            },
            cancelOnError: true,
          );

      _gyroscopeSubscription =
          gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 50))
              .listen(
                (event) {
                  _lastGyroscope = event;
                  _addSample();
                },
                onError: (Object error) {
                  debugPrint('Gyroscope error: $error');
                },
                cancelOnError: true,
              );
    } catch (_) {
      await stopRecording();
      rethrow;
    }
  }

  void _addSample() {
    if (!_isRecording) return;

    final accelerometer = _lastAccelerometer;
    final gyroscope = _lastGyroscope;

    // Do not generate fake values if a sensor is missing.
    if (accelerometer == null || gyroscope == null) {
      return;
    }

    final elapsedMs = _stopwatch.elapsedMilliseconds;

    // Keep approximately one sample per 100 milliseconds.
    if (elapsedMs - _lastSampleMs < 100) {
      return;
    }

    _lastSampleMs = elapsedMs;

    _samples.add({
      'tMs': elapsedMs,
      'ax': accelerometer.x,
      'ay': accelerometer.y,
      'az': accelerometer.z,
      'gx': gyroscope.x,
      'gy': gyroscope.y,
      'gz': gyroscope.z,
    });
  }

  // Stop listening and return a copy of the recorded samples.
  Future<List<Map<String, dynamic>>> stopRecording() async {
    _isRecording = false;
    _stopwatch.stop();

    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;

    return _samples.map((sample) => Map<String, dynamic>.from(sample)).toList();
  }

  // Save captured readings beside the local video.
  Future<String?> saveSensorData({
    required String projectId,
    required String clipId,
  }) async {
    if (kIsWeb || _samples.isEmpty) {
      return null;
    }

    final appDirectory = await getApplicationDocumentsDirectory();

    final directory = Directory(p.join(appDirectory.path, 'videos', projectId));

    await directory.create(recursive: true);

    final file = File(p.join(directory.path, '${clipId}_sensors.json'));

    await file.writeAsString(jsonEncode(_samples), flush: true);

    return file.absolute.path;
  }

  Future<void> dispose() async {
    await stopRecording();
  }
}
