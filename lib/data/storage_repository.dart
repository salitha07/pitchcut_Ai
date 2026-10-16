import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StorageRepository {
  StorageRepository({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in to upload or manage files.');
    }

    return user.uid;
  }

  // Get a reference to the signed-in user's storage folder.
  Reference _userFolder(String projectId) {
    return _storage
        .ref()
        .child('users')
        .child(_userId)
        .child('projects')
        .child(projectId);
  }

  // Upload a video file and return its download URL.
  Future<String> uploadVideo({
    required String projectId,
    required String clipId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    if (!await file.exists()) {
      throw StateError('Video file does not exist.');
    }

    final fileName = '$clipId.mp4';
    final reference = _userFolder(projectId).child('clips').child(fileName);

    final task = reference.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );

    task.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes;

      if (total > 0) {
        onProgress?.call(snapshot.bytesTransferred / total);
      }
    });

    final snapshot = await task;
    return snapshot.ref.getDownloadURL();
  }

  // Get the download URL of an uploaded video.
  Future<String> getVideoUrl({
    required String projectId,
    required String clipId,
  }) async {
    return _userFolder(projectId)
        .child('clips')
        .child('$clipId.mp4')
        .getDownloadURL();
  }

  // Delete an uploaded video.
  Future<void> deleteVideo({
    required String projectId,
    required String clipId,
  }) async {
    await _userFolder(projectId).child('clips').child('$clipId.mp4').delete();
  }

  // Upload a sensor-data file.
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

  // Delete a project's uploaded files.
  Future<void> deleteProjectFiles(String projectId) async {
    final projectFolder = _userFolder(projectId);
    final result = await projectFolder.listAll();

    for (final item in result.items) {
      await item.delete();
    }

    for (final prefix in result.prefixes) {
      await _deleteFolderContents(prefix);
    }
  }

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
