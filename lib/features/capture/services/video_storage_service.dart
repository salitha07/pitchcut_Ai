import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoStorageService {
  // Save a recorded or imported video to local app storage.
  Future<String> saveVideo({
    required XFile video,
    required String projectId,
    required String clipId,
  }) async {
    // The project contract currently supports Android
    // absolute local file paths, not browser blob URLs.
    if (kIsWeb) {
      throw UnsupportedError(
        'Permanent local video storage is not available '
        'in the Chrome prototype.',
      );
    }

    if (projectId.isEmpty || clipId.isEmpty) {
      throw ArgumentError('Project ID and Clip ID cannot be empty.');
    }

    // Find the app's documents directory.
    final appDirectory = await getApplicationDocumentsDirectory();

    // Create: app_documents/videos/<projectId>/
    final videoDirectory = Directory(
      p.join(appDirectory.path, 'videos', projectId),
    );

    await videoDirectory.create(recursive: true);

    // Preserve the actual video file extension.
    final originalExtension = p.extension(video.name).toLowerCase();

    final extension = originalExtension.isNotEmpty
        ? originalExtension
        : p.extension(video.path).toLowerCase();

    if (extension.isEmpty) {
      throw const FormatException('Video file extension is missing.');
    }

    // Construct the destination path.
    final savedPath = p.join(videoDirectory.path, '$clipId$extension');

    // Prevent accidental overwriting.
    if (await File(savedPath).exists()) {
      throw StateError('A video with this Clip ID already exists.');
    }

    // Copy the video to permanent local storage.
    try {
      await video.saveTo(savedPath);

      final savedFile = File(savedPath);

      // Verify that the saved file exists.
      if (!await savedFile.exists() || await savedFile.length() == 0) {
        throw FileSystemException(
          'Saved video is missing or empty.',
          savedPath,
        );
      }

      return savedFile.absolute.path;
    } catch (_) {
      // Remove an incomplete destination file.
      final incompleteFile = File(savedPath);

      if (await incompleteFile.exists()) {
        await incompleteFile.delete();
      }

      rethrow;
    }
  }
}
