import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../../data/project_repository.dart';
import '../../../models/project.dart';
import '../../../models/clip.dart';
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
    String? sensorDataPath,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Permanent project saving currently requires Android.',
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please log in before saving a project.');
    }

    if (title.trim().isEmpty) {
      throw ArgumentError('Project title cannot be empty.');
    }

    if (durationMs <= 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Video duration and dimensions must be positive.');
    }

    final projectId = _uuid.v4();
    final clipId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final project = Project(
      id: projectId,
      userId: user.uid,
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
      clipIds: const [],
    );

    // Save video locally first.
    final localPath = await _videoStorageService.saveVideo(
      video: video,
      projectId: projectId,
      clipId: clipId,
    );

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

    // Store metadata using M2's repositories.
    await _projectRepository.createProject(project);
    await _projectRepository.addClip(clip);

    return project.copyWith(
      clipIds: [clipId],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
