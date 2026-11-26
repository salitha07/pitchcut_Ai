import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:pitchcut_ai/features/capture/services/sensor_logging_service.dart';

void main() {
  Map<String, dynamic> validSample(int timeMs) {
    return {
      'tMs': timeMs,
      'ax': 0.1,
      'ay': 9.8,
      'az': 0.3,
      'gx': 0.01,
      'gy': 0.02,
      'gz': 0.03,
    };
  }

  group('Sensor JSON validation', () {
    test('accepts valid samples', () {
      expect(
        SensorLoggingService.validateSamples([
          validSample(0),
          validSample(100),
          validSample(200),
        ]),
        isTrue,
      );
    });

    test('rejects an empty collection', () {
      expect(SensorLoggingService.validateSamples([]), isFalse);
    });

    test('rejects missing sensor values', () {
      final sample = validSample(100);
      sample.remove('gx');

      expect(SensorLoggingService.isValidSample(sample), isFalse);
    });

    test('rejects negative timestamps', () {
      expect(SensorLoggingService.isValidSample(validSample(-1)), isFalse);
    });

    test('rejects duplicate timestamps', () {
      expect(
        SensorLoggingService.validateSamples([
          validSample(100),
          validSample(100),
        ]),
        isFalse,
      );
    });

    test('rejects decreasing timestamps', () {
      expect(
        SensorLoggingService.validateSamples([
          validSample(200),
          validSample(100),
        ]),
        isFalse,
      );
    });

    test('rejects non-finite numbers', () {
      final sample = validSample(100);
      sample['ax'] = double.nan;

      expect(SensorLoggingService.isValidSample(sample), isFalse);

      sample['ax'] = double.infinity;

      expect(SensorLoggingService.isValidSample(sample), isFalse);
    });

    test('rejects unexpected fields', () {
      final sample = validSample(100);
      sample['fakeValue'] = 42;

      expect(SensorLoggingService.isValidSample(sample), isFalse);
    });
  });

  group('Sensor event collection', () {
    late StreamController<AccelerometerEvent> accelerometerController;

    late StreamController<GyroscopeEvent> gyroscopeController;

    late SensorLoggingService service;

    AccelerometerEvent accelerometer() {
      return AccelerometerEvent(0.1, 9.8, 0.3, DateTime.now());
    }

    GyroscopeEvent gyroscope() {
      return GyroscopeEvent(0.01, 0.02, 0.03, DateTime.now());
    }

    setUp(() {
      accelerometerController = StreamController<AccelerometerEvent>.broadcast(
        sync: true,
      );

      gyroscopeController = StreamController<GyroscopeEvent>.broadcast(
        sync: true,
      );

      service = SensorLoggingService(
        accelerometerSource: () => accelerometerController.stream,
        gyroscopeSource: () => gyroscopeController.stream,
      );
    });

    tearDown(() async {
      await service.dispose();
      await accelerometerController.close();
      await gyroscopeController.close();
    });

    test('starts and stops recording', () async {
      await service.startRecording();

      expect(service.isRecording, isTrue);

      await service.stopRecording();

      expect(service.isRecording, isFalse);
    });

    test('does not invent missing gyroscope data', () async {
      await service.startRecording();

      accelerometerController.add(accelerometer());

      final result = await service.stopRecording();

      expect(result, isEmpty);
    });

    test('does not invent missing accelerometer data', () async {
      await service.startRecording();

      gyroscopeController.add(gyroscope());

      final result = await service.stopRecording();

      expect(result, isEmpty);
    });

    test('collects actual combined sensor readings', () async {
      await service.startRecording();

      accelerometerController.add(accelerometer());
      gyroscopeController.add(gyroscope());

      final result = await service.stopRecording();

      expect(result, isNotEmpty);
      expect(result.first['ax'], 0.1);
      expect(result.first['gx'], 0.01);

      expect(SensorLoggingService.validateSamples(result), isTrue);
    });

    test('does not collect after recording stops', () async {
      await service.startRecording();

      accelerometerController.add(accelerometer());
      gyroscopeController.add(gyroscope());

      await service.stopRecording();

      final oldCount = service.sampleCount;

      accelerometerController.add(accelerometer());
      gyroscopeController.add(gyroscope());

      expect(service.sampleCount, oldCount);
    });

    test('resets samples for a new recording', () async {
      await service.startRecording();

      accelerometerController.add(accelerometer());
      gyroscopeController.add(gyroscope());

      await service.stopRecording();

      expect(service.sampleCount, greaterThan(0));

      await service.startRecording();

      expect(service.sampleCount, 0);

      await service.stopRecording();
    });
  });
}
