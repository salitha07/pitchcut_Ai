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

/// Reads metadata with Flutter's existing video player plugin and always
/// disposes its temporary controller.
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
        // Preserve the metadata/initialization error if native disposal fails.
      }
    }
  }
}

abstract interface class M5VideoImporter {
  Future<Project> importVideo({required XFile video, required String title});
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

  @override
  Future<Project> importVideo({
    required XFile video,
    required String title,
  }) async {
    final path = video.path;
    if (path.trim().isEmpty || !await _fileExists(path)) {
      throw FileSystemException(
        'The selected video file is missing or inaccessible.',
        path,
      );
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Project title cannot be empty.');
    }

    final metadata = await metadataReader.read(video);
    if (metadata.durationMs <= 0 ||
        metadata.width <= 0 ||
        metadata.height <= 0) {
      throw const FormatException(
        'The selected video has invalid duration or dimensions.',
      );
    }

    return _captureProjectService.saveAsNewProject(
      video: video,
      title: cleanTitle,
      durationMs: metadata.durationMs,
      width: metadata.width,
      height: metadata.height,
      isImportedVideo: true,
    );
  }
}
