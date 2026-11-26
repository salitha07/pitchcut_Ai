import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/caption_repository.dart';
import 'package:pitchcut_ai/models/caption.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late CaptionRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'test-user-123'),
    );

    repository = CaptionRepository(firestore: firestore, auth: auth);
  });

  group('CaptionRepository', () {
    const projectId = 'project-1';

    const caption1 = Caption(
      id: 'caption-1',
      startMs: 2000,
      endMs: 4000,
      text: 'Second caption',
    );

    const caption2 = Caption(
      id: 'caption-2',
      startMs: 1000,
      endMs: 2000,
      text: 'First caption',
    );

    test('saves and loads a caption', () async {
      await repository.saveCaption(projectId, caption1);

      final captions = await repository.getCaptions(projectId);

      expect(captions, hasLength(1));
      expect(captions.first.id, 'caption-1');
      expect(captions.first.text, 'Second caption');
    });

    test('saves multiple captions in start-time order', () async {
      await repository.saveCaptions(projectId, [caption1, caption2]);

      final captions = await repository.getCaptions(projectId);

      expect(captions, hasLength(2));
      expect(captions.first.id, 'caption-2');
      expect(captions.last.id, 'caption-1');
    });

    test('updates an existing caption', () async {
      await repository.saveCaption(projectId, caption1);

      final updatedCaption = caption1.copyWith(text: 'Updated caption');

      await repository.updateCaption(projectId, updatedCaption);

      final captions = await repository.getCaptions(projectId);

      expect(captions.single.text, 'Updated caption');
    });

    test('deletes a caption', () async {
      await repository.saveCaption(projectId, caption1);

      await repository.deleteCaption(projectId, caption1.id);

      final captions = await repository.getCaptions(projectId);

      expect(captions, isEmpty);
    });

    test('deletes all captions for a project', () async {
      await repository.saveCaptions(projectId, [caption1, caption2]);

      await repository.deleteAllCaptions(projectId);

      final captions = await repository.getCaptions(projectId);

      expect(captions, isEmpty);
    });

    test('rejects access when the user is signed out', () async {
      final signedOutAuth = MockFirebaseAuth(signedIn: false);

      final signedOutRepository = CaptionRepository(
        firestore: firestore,
        auth: signedOutAuth,
      );

      expect(
        () => signedOutRepository.getCaptions(projectId),
        throwsA(isA<StateError>()),
      );
    });
  });
}
