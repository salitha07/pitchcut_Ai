
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

/// Metadata and source file for one imported video.
class CaptureVideoData {
  const CaptureVideoData({
    required this.video,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final XFile video;
  final int durationMs;
  final int width;
  final int height;
}

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

  /// Saves one video as a new project.
  /// Kept for compatibility with the existing single-video workflow.
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

    _validateVideoMetadata(durationMs, width, height);

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

      await _cleanupUncommittedFiles(projectId);

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

    try {
      await _projectRepository.createProject(project);
      await _projectRepository.addClip(clip);
    } catch (error, stackTrace) {
      debugPrint(
        'Firestore save failed for project $projectId and clip $clipId: $error',
      );
      debugPrint('Preserved local video: $localPath');

      Error.throwWithStackTrace(
        StateError(
          'Unable to complete Firebase project saving. '
          'Your local video has been preserved. '
          'Project ID: $projectId. '
          'Check Firebase records before attempting another save. '
          'Details: $error',
        ),
        stackTrace,
      );
    }

    return project.copyWith(
      clipIds: [clipId],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Saves multiple imported videos under one new project.
  ///
  /// Each source video receives its own Clip ID and order.
  /// All files are saved locally before Firestore writes begin.
  Future<Project> saveAsNewProjectWithVideos({
    required List<CaptureVideoData> videos,
    required String title,
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

    if (videos.isEmpty) {
      throw ArgumentError('At least one video is required.');
    }

    for (final item in videos) {
      _validateVideoMetadata(
        item.durationMs,
        item.width,
        item.height,
      );
    }

    final projectId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final project = Project(
      id: projectId,
      userId: user.uid,
      title: cleanTitle,
      createdAt: now,
      updatedAt: now,
      clipIds: const [],
    );

    final clips = <Clip>[];

    // Phase 1: Prepare every local video file.
    try {
      for (var index = 0; index < videos.length; index++) {
        final item = videos[index];
        final clipId = _uuid.v4();

        final localPath = await _videoStorageService.saveVideo(
          video: item.video,
          projectId: projectId,
          clipId: clipId,
        );

        clips.add(
          Clip(
            id: clipId,
            projectId: projectId,
            localPath: localPath,
            durationMs: item.durationMs,
            width: item.width,
            height: item.height,
            sensorDataPath: null,
            order: index,
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Multi-video local preparation failed: $error');

      await _cleanupUncommittedFiles(projectId);

      if (_isStorageFull(error)) {
        Error.throwWithStackTrace(
          const FileSystemException(
            'Not enough storage to save all videos. '
            'Free device space and try again.',
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }

    // Phase 2: Commit project and clip metadata.
    // Preserve local files if any Firebase write fails because the
    // server may have committed some of the writes already.
    try {
      await _projectRepository.createProject(project);

      for (final clip in clips) {
        await _projectRepository.addClip(clip);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Multi-video Firebase save failed for project $projectId: $error',
      );

      for (final clip in clips) {
        debugPrint('Preserved local video: ${clip.localPath}');
      }

      Error.throwWithStackTrace(
        StateError(
          'Unable to complete Firebase project saving. '
          'Local videos have been preserved. '
          'Project ID: $projectId. '
          'Check Firebase records before retrying. '
          'Details: $error',
        ),
        stackTrace,
      );
    }

    return project.copyWith(
      clipIds: clips.map((clip) => clip.id).toList(growable: false),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  void _validateVideoMetadata(int durationMs, int width, int height) {
    if (durationMs <= 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Invalid video duration or dimensions.');
    }
  }

  Future<void> _cleanupUncommittedFiles(String projectId) async {
    try {
      await _videoStorageService.deleteUncommittedProjectFiles(
        projectId: projectId,
      );
    } catch (cleanupError) {
      debugPrint(
        'Local cleanup failed for $projectId: $cleanupError',
      );
    }
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
