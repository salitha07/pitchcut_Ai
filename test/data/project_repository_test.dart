import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/project_repository.dart';
import 'package:pitchcut_ai/models/clip.dart';
import 'package:pitchcut_ai/models/project.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ProjectRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();

    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'test-user-123'),
    );

    repository = ProjectRepository(firestore: firestore, auth: auth);
  });

  const project = Project(
    id: 'project-1',
    userId: 'test-user-123',
    title: 'My First Project',
    createdAt: '2026-10-15T10:00:00.000Z',
    updatedAt: '2026-10-15T10:00:00.000Z',
  );

  const clip1 = Clip(
    id: 'clip-1',
    projectId: 'project-1',
    localPath: '/videos/clip1.mp4',
    durationMs: 5000,
    width: 1920,
    height: 1080,
    order: 1,
  );

  const clip2 = Clip(
    id: 'clip-2',
    projectId: 'project-1',
    localPath: '/videos/clip2.mp4',
    durationMs: 7000,
    width: 1920,
    height: 1080,
    order: 0,
  );

  group('ProjectRepository', () {
    test('creates and loads a project', () async {
      await repository.createProject(project);

      final projects = await repository.getProjects();

      expect(projects, hasLength(1));
      expect(projects.first.id, 'project-1');
      expect(projects.first.title, 'My First Project');
      expect(projects.first.userId, 'test-user-123');
    });

    test('updates an existing project', () async {
      await repository.createProject(project);

      final updatedProject = project.copyWith(title: 'Updated Project');

      await repository.updateProject(updatedProject);

      final projects = await repository.getProjects();

      expect(projects.single.title, 'Updated Project');
    });

    test('rejects updating another user project', () async {
      await repository.createProject(project);

      final otherUserProject = project.copyWith(userId: 'another-user');

      expect(
        () => repository.updateProject(otherUserProject),
        throwsA(isA<StateError>()),
      );
    });

    test('adds clips and returns them in order', () async {
      await repository.createProject(project);

      await repository.addClip(clip1);
      await repository.addClip(clip2);

      final clips = await repository.getClips('project-1');

      expect(clips, hasLength(2));
      expect(clips.first.id, 'clip-2');
      expect(clips.last.id, 'clip-1');

      final projects = await repository.getProjects();

      expect(projects.single.clipIds, containsAll(['clip-1', 'clip-2']));
    });

    test('updates a clip', () async {
      await repository.createProject(project);
      await repository.addClip(clip1);

      final updatedClip = clip1.copyWith(localPath: '/videos/updated.mp4');

      await repository.updateClip(updatedClip);

      final clips = await repository.getClips('project-1');

      expect(clips.single.localPath, '/videos/updated.mp4');
    });

    test('deletes a clip and removes its ID from project', () async {
      await repository.createProject(project);
      await repository.addClip(clip1);

      await repository.deleteClip('project-1', 'clip-1');

      final clips = await repository.getClips('project-1');
      final projects = await repository.getProjects();

      expect(clips, isEmpty);
      expect(projects.single.clipIds, isNot(contains('clip-1')));
    });

    test('deletes a project and its clips', () async {
      await repository.createProject(project);
      await repository.addClip(clip1);

      await repository.deleteProject('project-1');

      final projects = await repository.getProjects();

      expect(projects, isEmpty);
    });

    test('throws when adding a clip to a missing project', () async {
      expect(() => repository.addClip(clip1), throwsA(isA<StateError>()));
    });

    test('rejects access when signed out', () async {
      final signedOutRepository = ProjectRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: false),
      );

      expect(
        () => signedOutRepository.getProjects(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
