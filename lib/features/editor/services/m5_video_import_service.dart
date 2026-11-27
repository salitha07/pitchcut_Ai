import 'dart:io';

import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

import '../../capture/services/capture_project_service.dart';
import '../../../models/project.dart';

class VideoMetadata {
  const VideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final int durationMs;
  final int width;
  final int height;
}

abstract interface class M5VideoMetadataReader {
  Future<VideoMetadata> read(XFile video);
}

/// Reads metadata with Flutter's video player plugin and disposes
/// its temporary controller after reading.
class VideoPlayerMetadataReader implements M5VideoMetadataReader {
  const VideoPlayerMetadataReader();

  @override
  Future<VideoMetadata> read(XFile video) async {
    final controller = VideoPlayerController.file(File(video.path));

    try {
      await controller.initialize();
      final value = controller.value;

      return VideoMetadata(
        durationMs: value.duration.inMilliseconds,
        width: value.size.width.round(),
        height: value.size.height.round(),
      );
    } finally {
      try {
        await controller.dispose();
      } catch (_) {
        // Preserve the original metadata/initialization error.
      }
    }
  }
}

abstract interface class M5VideoImporter {
  Future<Project> importVideo({required XFile video, required String title});

  Future<Project> importVideos({
    required List<XFile> videos,
    required String title,
  });
}

/// M5 import orchestration that delegates project/file creation to M3.
class M5VideoImportService implements M5VideoImporter {
  M5VideoImportService({
    CaptureProjectService? captureProjectService,
    this.metadataReader = const VideoPlayerMetadataReader(),
    Future<bool> Function(String path)? fileExists,
  }) : _captureProjectService =
           captureProjectService ?? CaptureProjectService(),
       _fileExists = fileExists ?? _defaultFileExists;

  final CaptureProjectService _captureProjectService;
  final M5VideoMetadataReader metadataReader;
  final Future<bool> Function(String path) _fileExists;

  static Future<bool> _defaultFileExists(String path) => File(path).exists();

  /// Imports one video into a new project.
  /// Kept for existing single-video workflows.
  @override
  Future<Project> importVideo({
    required XFile video,
    required String title,
  }) async {
    _validateTitle(title);
    await _validateFile(video);

    final metadata = await metadataReader.read(video);
    _validateMetadata(metadata);

    return _captureProjectService.saveAsNewProject(
      video: video,
      title: title.trim(),
      durationMs: metadata.durationMs,
      width: metadata.width,
      height: metadata.height,
      isImportedVideo: true,
    );
  }

  /// Imports multiple videos into one new project.
  ///
  /// Every video is validated and its metadata is read before the
  /// project service starts saving files or writing Firestore records.
  @override
  Future<Project> importVideos({
    required List<XFile> videos,
    required String title,
  }) async {
    _validateTitle(title);

    if (videos.isEmpty) {
      throw ArgumentError('Select at least one video to import.');
    }

    final captureVideos = <CaptureVideoData>[];

    // Validate all selected files before starting the import.
    for (final video in videos) {
      await _validateFile(video);
    }

    // Read metadata for every video before creating the project.
    for (final video in videos) {
      final metadata = await metadataReader.read(video);
      _validateMetadata(metadata);

      captureVideos.add(
        CaptureVideoData(
          video: video,
          durationMs: metadata.durationMs,
          width: metadata.width,
          height: metadata.height,
        ),
      );
    }

    return _captureProjectService.saveAsNewProjectWithVideos(
      videos: captureVideos,
      title: title.trim(),
    );
  }

  void _validateTitle(String title) {
    if (title.trim().isEmpty) {
      throw ArgumentError('Project title cannot be empty.');
    }
  }

  Future<void> _validateFile(XFile video) async {
    final path = video.path;

    if (path.trim().isEmpty || !await _fileExists(path)) {
      throw FileSystemException(
        'The selected video file is missing or inaccessible.',
        path,
      );
    }
  }

  void _validateMetadata(VideoMetadata metadata) {
    if (metadata.durationMs <= 0 ||
        metadata.width <= 0 ||
        metadata.height <= 0) {
      throw const FormatException(
        'A selected video has invalid duration or dimensions.',
      );
    }
  }
}
