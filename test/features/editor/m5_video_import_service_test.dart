import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/project_repository.dart';
import 'package:pitchcut_ai/features/capture/services/capture_project_service.dart';
import 'package:pitchcut_ai/features/capture/services/sensor_logging_service.dart';
import 'package:pitchcut_ai/features/editor/services/m5_video_import_service.dart';
import 'package:pitchcut_ai/models/project.dart';

void main() {
  const project = Project(
    id: 'imported-project',
    userId: 'import-user',
    title: 'Imported project',
    createdAt: '2026-11-08T00:00:00.000Z',
    updatedAt: '2026-11-08T00:00:00.000Z',
    clipIds: ['imported-clip'],
  );
  final video = XFile('/test/library-clip.mp4', name: 'library-clip.mp4');

  test(
    'rejects missing source before reading metadata or calling M3',
    () async {
      final reader = FakeMetadataReader(
        const VideoMetadata(durationMs: 4000, width: 1920, height: 1080),
      );
      final capture = RecordingCaptureProjectService(project);
      final service = M5VideoImportService(
        captureProjectService: capture,
        metadataReader: reader,
        fileExists: (_) async => false,
      );

      await expectLater(
        service.importVideo(video: video, title: 'Imported'),
        throwsA(isA<FileSystemException>()),
      );
      expect(reader.calls, 0);
      expect(capture.calls, 0);
    },
  );

  test('invalid metadata prevents project creation', () async {
    final reader = FakeMetadataReader(
      const VideoMetadata(durationMs: 0, width: 1920, height: 1080),
    );
    final capture = RecordingCaptureProjectService(project);
    final service = M5VideoImportService(
      captureProjectService: capture,
      metadataReader: reader,
      fileExists: (_) async => true,
    );

    await expectLater(
      service.importVideo(video: video, title: 'Imported'),
      throwsA(isA<FormatException>()),
    );
    expect(reader.calls, 1);
    expect(capture.calls, 0);
  });

  test('forwards title and metadata to M3 as an imported video', () async {
    final reader = FakeMetadataReader(
      const VideoMetadata(durationMs: 12345, width: 3840, height: 2160),
    );
    final capture = RecordingCaptureProjectService(project);
    final service = M5VideoImportService(
      captureProjectService: capture,
      metadataReader: reader,
      fileExists: (_) async => true,
    );

    final saved = await service.importVideo(video: video, title: '  Match  ');

    expect(saved.id, project.id);
    expect(capture.calls, 1);
    expect(capture.video?.path, video.path);
    expect(capture.title, 'Match');
    expect(capture.durationMs, 12345);
    expect(capture.width, 3840);
    expect(capture.height, 2160);
    expect(capture.isImportedVideo, isTrue);
  });

  test('rejects an empty title without reading metadata', () async {
    final reader = FakeMetadataReader(
      const VideoMetadata(durationMs: 4000, width: 1920, height: 1080),
    );
    final capture = RecordingCaptureProjectService(project);
    final service = M5VideoImportService(
      captureProjectService: capture,
      metadataReader: reader,
      fileExists: (_) async => true,
    );

    await expectLater(
      service.importVideo(video: video, title: '  '),
      throwsArgumentError,
    );
    expect(reader.calls, 0);
    expect(capture.calls, 0);
  });

  test('propagates ambiguous M3 write failure without retrying', () async {
    final reader = FakeMetadataReader(
      const VideoMetadata(durationMs: 4000, width: 1920, height: 1080),
    );
    final capture = RecordingCaptureProjectService(
      project,
      failure: StateError(
        'Unable to complete Firebase project saving. Project ID: partial-id.',
      ),
    );
    final service = M5VideoImportService(
      captureProjectService: capture,
      metadataReader: reader,
      fileExists: (_) async => true,
    );

    await expectLater(
      service.importVideo(video: video, title: 'Imported'),
      throwsA(isA<StateError>()),
    );
    expect(capture.calls, 1);
  });
}

class FakeMetadataReader implements M5VideoMetadataReader {
  FakeMetadataReader(this.metadata);

  final VideoMetadata metadata;
  int calls = 0;

  @override
  Future<VideoMetadata> read(XFile video) async {
    calls++;
    return metadata;
  }
}

class RecordingCaptureProjectService extends CaptureProjectService {
  RecordingCaptureProjectService(Project result, {Object? failure})
    : this._(
        result,
        failure,
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'import-user'),
        ),
        FakeFirebaseFirestore(),
      );

  RecordingCaptureProjectService._(
    this.result,
    this.failure,
    MockFirebaseAuth auth,
    FakeFirebaseFirestore firestore,
  ) : super(
        projectRepository: ProjectRepository(firestore: firestore, auth: auth),
        auth: auth,
      );

  final Project result;
  final Object? failure;
  int calls = 0;
  XFile? video;
  String? title;
  int? durationMs;
  int? width;
  int? height;
  bool? isImportedVideo;

  @override
  Future<Project> saveAsNewProject({
    required XFile video,
    required String title,
    required int durationMs,
    required int width,
    required int height,
    SensorLoggingService? sensorService,
    bool isImportedVideo = false,
  }) async {
    calls++;
    this.video = video;
    this.title = title;
    this.durationMs = durationMs;
    this.width = width;
    this.height = height;
    this.isImportedVideo = isImportedVideo;
    if (failure case final error?) throw error;
    return result;
  }
}
