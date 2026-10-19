import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StorageRepository {
  StorageRepository({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  // Get the signed-in user's ID.
  String get _userId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in to upload or manage files.');
    }

    return user.uid;
  }

  // Get a reference to the signed-in user's project folder.
  // Check authentication before accessing Firebase Storage.
  Reference _userFolder(String projectId) {
    final userId = _userId;

    return _storage
        .ref()
        .child('users')
        .child(userId)
        .child('projects')
        .child(projectId);
  }

  // Upload a video and return its download URL.
  Future<String> uploadVideo({
    required String projectId,
    required String clipId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    if (!await file.exists()) {
      throw StateError('Video file does not exist.');
    }

    final reference = _userFolder(projectId)
        .child('clips')
        .child('$clipId.mp4');

    final task = reference.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );

    final subscription = task.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes;

      if (total > 0) {
        onProgress?.call(snapshot.bytesTransferred / total);
      }
    });

    try {
      final snapshot = await task;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      onProgress?.call(1.0);

      return downloadUrl;
    } finally {
      await subscription.cancel();
    }
  }

  // Get the download URL of an uploaded video.
  Future<String> getVideoUrl({
    required String projectId,
    required String clipId,
  }) async {
    final reference = _userFolder(projectId)
        .child('clips')
        .child('$clipId.mp4');

    return reference.getDownloadURL();
  }

  // Delete an uploaded video.
  Future<void> deleteVideo({
    required String projectId,
    required String clipId,
  }) async {
    final reference = _userFolder(projectId)
        .child('clips')
        .child('$clipId.mp4');

    await reference.delete();
  }

  // Upload sensor data in JSON format.
  Future<String> uploadSensorData({
    required String projectId,
    required String clipId,
    required File file,
  }) async {
    if (!await file.exists()) {
      throw StateError('Sensor data file does not exist.');
    }

    final reference = _userFolder(projectId)
        .child('clips')
        .child('$clipId.json');

    final snapshot = await reference.putFile(
      file,
      SettableMetadata(contentType: 'application/json'),
    );

    return snapshot.ref.getDownloadURL();
  }

  // Delete all files belonging to a project.
  Future<void> deleteProjectFiles(String projectId) async {
    final projectFolder = _userFolder(projectId);

    await _deleteFolderContents(projectFolder);
  }

  // Recursively delete files inside a Storage folder.
  Future<void> _deleteFolderContents(Reference folder) async {
    final result = await folder.listAll();

    for (final item in result.items) {
      await item.delete();
    }

    for (final prefix in result.prefixes) {
      await _deleteFolderContents(prefix);
    }
  }
}
