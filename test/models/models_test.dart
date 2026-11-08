import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/models/project.dart';
import 'package:pitchcut_ai/models/clip.dart';
import 'package:pitchcut_ai/models/caption.dart';
import 'package:pitchcut_ai/models/pause_segment.dart';
import 'package:pitchcut_ai/models/performance_report.dart';

void main() {
  group('Project model', () {
    test('JSON round trip works', () {
      const project = Project(
        id: 'p1',
        userId: 'u1',
        title: 'My video',
        createdAt: '2026-10-14T10:00:00Z',
        updatedAt: '2026-10-14T10:00:00Z',
        clipIds: ['c1', 'c2'],
      );

      final restored = Project.fromJson(project.toJson());
      expect(restored.toJson(), project.toJson());
    });

    test('copyWith updates title', () {
      const project = Project(
        id: 'p1',
        userId: 'u1',
        title: 'Old title',
        createdAt: '2026-10-14T10:00:00Z',
        updatedAt: '2026-10-14T10:00:00Z',
      );

      expect(project.copyWith(title: 'New title').title, 'New title');
      expect(project.title, 'Old title');
    });

    test('copyWith can clear nullable paths', () {
      const project = Project(
        id: 'p1',
        userId: 'u1',
        title: 'Video',
        createdAt: '2026-10-14T10:00:00Z',
        updatedAt: '2026-10-14T10:00:00Z',
        exportedVideoPath: '/videos/export.mp4',
      );

      final updated = project.copyWith(clearExportedVideoPath: true);

      expect(updated.exportedVideoPath, isNull);
      expect(project.exportedVideoPath, '/videos/export.mp4');
    });

    test('copyWith can clear latest report ID', () {
      const project = Project(
        id: 'p1',
        userId: 'u1',
        title: 'Video',
        createdAt: '2026-10-14T10:00:00Z',
        updatedAt: '2026-10-14T10:00:00Z',
        latestReportId: 'r1',
      );

      expect(
        project.copyWith(clearLatestReportId: true).latestReportId,
        isNull,
      );
    });
  });

  group('Clip model', () {
    test('JSON round trip works', () {
      const clip = Clip(
        id: 'c1',
        projectId: 'p1',
        localPath: '/videos/clip.mp4',
        durationMs: 5000,
        width: 1920,
        height: 1080,
        sensorDataPath: '/videos/c1_sensors.json',
        order: 0,
      );

      expect(Clip.fromJson(clip.toJson()).toJson(), clip.toJson());
    });

    test('copyWith updates order', () {
      const clip = Clip(
        id: 'c1',
        projectId: 'p1',
        localPath: '/videos/clip.mp4',
        durationMs: 5000,
        width: 1920,
        height: 1080,
        order: 0,
      );

      expect(clip.copyWith(order: 2).order, 2);
      expect(clip.order, 0);
    });

    test('copyWith can clear sensor data path', () {
      const clip = Clip(
        id: 'c1',
        projectId: 'p1',
        localPath: '/videos/clip.mp4',
        durationMs: 5000,
        width: 1920,
        height: 1080,
        sensorDataPath: '/videos/sensors.json',
        order: 0,
      );

      final updated = clip.copyWith(clearSensorDataPath: true);

      expect(updated.sensorDataPath, isNull);
      expect(clip.sensorDataPath, '/videos/sensors.json');
    });
  });

  group('Caption model', () {
    test('JSON round trip works', () {
      const caption = Caption(
        id: 'cap1',
        startMs: 1000,
        endMs: 2500,
        text: 'Hello everyone',
      );

      expect(Caption.fromJson(caption.toJson()).toJson(), caption.toJson());
    });

    test('copyWith updates caption text', () {
      const caption = Caption(
        id: 'cap1',
        startMs: 1000,
        endMs: 2500,
        text: 'Hello',
      );

      expect(caption.copyWith(text: 'Welcome').text, 'Welcome');
    });
  });

  group('PauseSegment model', () {
    test('JSON round trip works', () {
      const pause = PauseSegment(startMs: 1000, endMs: 3000);

      expect(PauseSegment.fromJson(pause.toJson()).toJson(), pause.toJson());
    });

    test('copyWith updates times', () {
      const pause = PauseSegment(startMs: 1000, endMs: 3000);
      final updated = pause.copyWith(startMs: 1500);

      expect(updated.startMs, 1500);
      expect(updated.endMs, 3000);
    });
  });

  group('PerformanceReport model', () {
    test('JSON round trip preserves nested pauses and tips', () {
      const report = PerformanceReport(
        id: 'r1',
        projectId: 'p1',
        createdAt: '2026-10-14T10:00:00Z',
        score: 85,
        pauses: [PauseSegment(startMs: 1000, endMs: 3000)],
        faceScore: 90,
        stabilityScore: 80,
        paceScore: -1,
        tips: ['Look at the camera', 'Reduce long pauses'],
      );

      final restored = PerformanceReport.fromJson(report.toJson());

      expect(restored.toJson(), report.toJson());
      expect(restored.pauses.first.startMs, 1000);
      expect(restored.tips.length, 2);
    });

    test('copyWith updates score', () {
      const report = PerformanceReport(
        id: 'r1',
        projectId: 'p1',
        createdAt: '2026-10-14T10:00:00Z',
        score: 70,
        faceScore: 75,
        stabilityScore: 80,
        paceScore: 60,
      );

      expect(report.copyWith(score: 90).score, 90);
      expect(report.score, 70);
    });
  });
}
