import 'dart:io';

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

    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in before saving a project.');
    }

    final cleanTitle = title.trim();

    if (cleanTitle.isEmpty) {
      throw ArgumentError('Project title cannot be empty.');
    }

    if (durationMs <= 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Invalid video duration or dimensions.');
    }

    final projectId = _uuid.v4();
    final clipId = _uuid.v4();

    final now = DateTime.now().toUtc().toIso8601String();

    final project = Project(
      id: projectId,
      userId: user.uid,
      title: cleanTitle,
      createdAt: now,
      updatedAt: now,
      clipIds: const [],
    );

    late final String localPath;
    String? sensorDataPath;

    // ==========================================
    // PHASE 1: LOCAL FILE PREPARATION
    // ==========================================
    //
    // No Firestore writes have started here.
    // Cleanup is safe because these IDs are new.

    try {
      localPath = await _videoStorageService.saveVideo(
        video: video,
        projectId: projectId,
        clipId: clipId,
      );

      if (!isImportedVideo &&
          sensorService != null &&
          sensorService.sampleCount > 0) {
        sensorDataPath = await sensorService.saveSensorData(
          projectId: projectId,
          clipId: clipId,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Local project preparation failed: $error');

      try {
        await _videoStorageService.deleteUncommittedProjectFiles(
          projectId: projectId,
        );
      } catch (cleanupError) {
        debugPrint(
          'Local cleanup failed for $projectId: '
          '$cleanupError',
        );
      }

      if (_isStorageFull(error)) {
        Error.throwWithStackTrace(
          const FileSystemException(
            'Not enough storage to save the project. '
            'Free device space and try again.',
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }

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

    // ==========================================
    // PHASE 2: FIRESTORE METADATA WRITES
    // ==========================================
    //
    // These repository calls are currently separate.
    // A failed call may have an uncertain server result.
    //
    // Therefore DO NOT delete local project files here.
    // They may already be referenced by Firestore data.

    try {
      await _projectRepository.createProject(project);

      await _projectRepository.addClip(clip);
    } catch (error, stackTrace) {
      debugPrint(
        'Firestore save failed for project $projectId '
        'and clip $clipId: $error',
      );

      debugPrint('Preserved local video: $localPath');

      if (sensorDataPath != null) {
        debugPrint('Preserved sensor file: $sensorDataPath');
      }

      Error.throwWithStackTrace(
        StateError(
          'Unable to complete Firebase project saving. '
          'Your local video has been preserved. '
          'Project ID: $projectId. '
          'Do not uninstall the app or clear app data. '
          'Check Firebase connection and project records '
          'before attempting another save. '
          'Details: $error',
        ),
        stackTrace,
      );
    }

    // ==========================================
    // SAVE COMPLETED
    // ==========================================

    return project.copyWith(
      clipIds: [clipId],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  bool _isStorageFull(Object error) {
    if (error is FileSystemException && error.osError?.errorCode == 28) {
      return true;
    }

    final description = error.toString().toLowerCase();

    return description.contains('no space left on device') ||
        description.contains('not enough storage') ||
        description.contains('not enough device storage') ||
        description.contains('storage full');
  }
}
