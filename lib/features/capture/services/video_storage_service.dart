import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoStorageService {
  /// Save a recorded or imported video inside app documents.
  Future<String> saveVideo({
    required XFile video,
    required String projectId,
    required String clipId,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Permanent local video storage is not available '
        'in the Chrome prototype.',
      );
    }

    if (projectId.trim().isEmpty || clipId.trim().isEmpty) {
      throw ArgumentError('Project ID and Clip ID cannot be empty.');
    }

    final appDirectory = await getApplicationDocumentsDirectory();

    final projectDirectory = Directory(
      p.join(appDirectory.path, 'videos', projectId),
    );

    final originalExtension = p.extension(video.name).toLowerCase();

    final sourceExtension = p.extension(video.path).toLowerCase();

    final extension = originalExtension.isNotEmpty
        ? originalExtension
        : sourceExtension;

    if (extension.isEmpty) {
      throw const FormatException('Video file extension is missing.');
    }

    final savedPath = p.join(projectDirectory.path, '$clipId$extension');

    final destination = File(savedPath);

    try {
      await projectDirectory.create(recursive: true);

      if (await destination.exists()) {
        throw StateError('A video with this Clip ID already exists.');
      }

      await video.saveTo(savedPath);

      if (!await destination.exists()) {
        throw FileSystemException('Saved video was not found.', savedPath);
      }

      final fileSize = await destination.length();

      if (fileSize <= 0) {
        throw FileSystemException('Saved video is empty.', savedPath);
      }

      return destination.absolute.path;
    } on FileSystemException catch (e) {
      await _deleteIncompleteFile(destination);

      if (_isStorageFull(e)) {
        throw const FileSystemException(
          'Not enough device storage to save this video. '
          'Free some storage space and try again.',
        );
      }

      rethrow;
    } catch (_) {
      await _deleteIncompleteFile(destination);
      rethrow;
    }
  }

  /// Delete only an incomplete file created by a failed copy.
  Future<void> _deleteIncompleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Unable to remove incomplete video: $e');
    }
  }

  /// Detect Android/Linux ENOSPC.
  bool _isStorageFull(FileSystemException error) {
    const noSpaceLeftOnDevice = 28;

    final errorCode = error.osError?.errorCode;

    if (errorCode == noSpaceLeftOnDevice) {
      return true;
    }

    final message = error.toString().toLowerCase();

    return message.contains('no space left on device') ||
        message.contains('not enough space') ||
        message.contains('storage full');
  }

  /// Remove project-local files only when the caller knows
  /// that no Firestore metadata write has been attempted.
  ///
  /// Never call this after an uncertain Firebase write result.
  Future<void> deleteUncommittedProjectFiles({
    required String projectId,
  }) async {
    if (kIsWeb) {
      return;
    }

    if (projectId.trim().isEmpty ||
        !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(projectId)) {
      throw ArgumentError('Invalid project ID for cleanup.');
    }

    final appDirectory = await getApplicationDocumentsDirectory();

    final projectDirectory = Directory(
      p.join(appDirectory.path, 'videos', projectId),
    );

    if (await projectDirectory.exists()) {
      await projectDirectory.delete(recursive: true);
    }
  }
}
