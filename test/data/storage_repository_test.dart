import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pitchcut_ai/data/storage_repository.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  late MockFirebaseStorage storage;
  late MockFirebaseAuth auth;
  late StorageRepository repository;

  setUp(() {
    storage = MockFirebaseStorage();
    auth = MockFirebaseAuth();

    when(() => auth.currentUser).thenReturn(null);

    repository = StorageRepository(storage: storage, auth: auth);
  });

  group('StorageRepository', () {
    test('uploadVideo rejects a file that does not exist', () async {
      final file = File('${Directory.systemTemp.path}/missing_video_test.mp4');

      await expectLater(
        repository.uploadVideo(
          projectId: 'project-1',
          clipId: 'clip-1',
          file: file,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('uploadSensorData rejects a file that does not exist', () async {
      final file = File(
        '${Directory.systemTemp.path}/missing_sensor_test.json',
      );

      await expectLater(
        repository.uploadSensorData(
          projectId: 'project-1',
          clipId: 'clip-1',
          file: file,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('getVideoUrl rejects a signed-out user', () async {
      await expectLater(
        repository.getVideoUrl(projectId: 'project-1', clipId: 'clip-1'),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => storage.ref());
    });

    test('deleteVideo rejects a signed-out user', () async {
      await expectLater(
        repository.deleteVideo(projectId: 'project-1', clipId: 'clip-1'),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => storage.ref());
    });

    test('deleteProjectFiles rejects a signed-out user', () async {
      await expectLater(
        repository.deleteProjectFiles('project-1'),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => storage.ref());
    });
  });
}
