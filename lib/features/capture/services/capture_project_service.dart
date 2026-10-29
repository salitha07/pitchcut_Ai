import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/project_repository.dart';
import '../../../models/clip.dart';
import '../../../models/project.dart';
import 'sensor_logging_service.dart';
import 'video_storage_service.dart';

class CaptureProjectService {
  CaptureProjectService({
    ProjectRepository? projectRepository,
    VideoStorageService? videoStorageService,
    FirebaseAuth? auth,
  }) : _projectRepository = projectRepository ?? ProjectRepository(),
       _videoStorageService = videoStorageService ?? VideoStorageService(),
       _auth = auth ?? FirebaseAuth.instance;

  final ProjectRepository _projectRepository;
  final VideoStorageService _videoStorageService;
  final FirebaseAuth _auth;

  final Uuid _uuid = const Uuid();

  Future<Project> saveAsNewProject({
    required XFile video,
    required String title,
    required int durationMs,
    required int width,
    required int height,
    SensorLoggingService? sensorService,
    bool isImportedVideo = false,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Permanent project saving currently requires Android.',
      );
    }

    // Get the currently authenticated Firebase user.
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in before saving a project.');
    }

    if (title.trim().isEmpty) {
      throw ArgumentError('Project title cannot be empty.');
    }

    if (durationMs <= 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Invalid video duration or dimensions.');
    }

    // Generate IDs once for all related files and metadata.
    final projectId = _uuid.v4();
    final clipId = _uuid.v4();

    final now = DateTime.now().toUtc().toIso8601String();

    // Create Project metadata.
    final project = Project(
      id: projectId,
      userId: user.uid,
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
      clipIds: const [],
    );

    // Save the recorded or imported video locally.
    final localPath = await _videoStorageService.saveVideo(
      video: video,
      projectId: projectId,
      clipId: clipId,
    );

    // Save motion sensor data only for recorded videos.
    // Imported videos do not have original sensor readings.
    String? sensorDataPath;

    if (!isImportedVideo &&
        sensorService != null &&
        sensorService.sampleCount > 0) {
      sensorDataPath = await sensorService.saveSensorData(
        projectId: projectId,
        clipId: clipId,
      );
    }

    // Create Clip metadata using actual saved paths.
    final clip = Clip(
      id: clipId,
      projectId: projectId,
      localPath: localPath,
      durationMs: durationMs,
      width: width,
      height: height,
      sensorDataPath: sensorDataPath,
      order: 0,
    );

    // Save metadata using Member 2's repository.
    // This does not upload the actual video to Firebase.
    await _projectRepository.createProject(project);

    await _projectRepository.addClip(clip);

    return project.copyWith(
      clipIds: [clipId],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
