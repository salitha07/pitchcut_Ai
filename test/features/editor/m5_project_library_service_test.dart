import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/project_repository.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/services/m5_project_library_service.dart';
import 'package:pitchcut_ai/models/clip.dart';
import 'package:pitchcut_ai/models/project.dart';

void main() {
  late Directory root;
  late Directory sources;
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ProjectRepository repository;
  late EditorProjectStore store;
  late M5ProjectLibraryService service;

  const project = Project(
    id: 'shared-project-1',
    userId: 'm5-user',
    title: 'Shared project',
    createdAt: '2026-11-08T00:00:00.000Z',
    updatedAt: '2026-11-08T00:00:00.000Z',
    clipIds: ['later-clip', 'first-clip'],
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('m5-project-library-');
    sources = Directory('${root.path}/videos')..createSync(recursive: true);
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'm5-user'));
    repository = ProjectRepository(firestore: firestore, auth: auth);
    store = EditorProjectStore(rootDirectory: root);
    service = M5ProjectLibraryService(
      projectRepository: repository,
      projectStore: store,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Clip> makeClip({
    required String id,
    required String path,
    required int order,
  }) async {
    final file = File(path)..writeAsBytesSync([1, 2, 3]);
    return Clip(
      id: id,
      projectId: project.id,
      localPath: file.path,
      durationMs: 5000,
      width: 1920,
      height: 1080,
      order: order,
    );
  }

  Future<File> snapshotFile(String projectId) async {
    final encoded = base64Url
        .encode(utf8.encode(projectId))
        .replaceAll('=', '');
    return File('${root.path}/editor_projects/$encoded.json');
  }

  test('lists M2 projects through the existing repository', () async {
    await repository.createProject(project);

    final projects = await service.getProjects();

    expect(projects.map((item) => item.id), [project.id]);
    expect(projects.single.title, project.title);
  });

  test('M2 listing leaves legacy M5 snapshots available', () async {
    await repository.createProject(project);
    const legacyId = '/legacy/videos/old-project.mp4';
    await store.save(
      projectId: legacyId,
      clips: const [
        VideoClip(
          path: legacyId,
          name: 'old-project.mp4',
          duration: Duration(seconds: 5),
        ),
      ],
      selectedClipIndex: 0,
      trimRange: const TrimRange(
        start: Duration.zero,
        end: Duration(seconds: 5),
      ),
    );

    await service.getProjects();

    expect(await store.listProjectIds(), contains(legacyId));
    expect((await store.load(legacyId))?.clips.single.name, 'old-project.mp4');
  });

  test('selection loads ordered clips and preserves M2 identities', () async {
    await repository.createProject(project);
    final first = await makeClip(
      id: 'first-clip',
      path: '${sources.path}/first.mp4',
      order: 0,
    );
    final later = await makeClip(
      id: 'later-clip',
      path: '${sources.path}/later.mp4',
      order: 2,
    );
    await repository.addClip(later);
    await repository.addClip(first);

    final selection = await service.selectProject(project);

    expect(selection.canOpen, isTrue);
    expect(selection.project.id, project.id);
    expect(selection.sourceClips.map((clip) => clip.id), [first.id, later.id]);
    expect(selection.timeline!.projectId, project.id);
    expect(selection.timeline!.clips.map((clip) => clip.sourceClipId), [
      first.id,
      later.id,
    ]);
    expect(
      selection.timeline!.clips.map((clip) => clip.timelineItemId).toSet(),
      hasLength(2),
    );
  });

  test('empty projects return an explicit non-openable selection', () async {
    await repository.createProject(project);

    final selection = await service.selectProject(project);

    expect(selection.canOpen, isFalse);
    expect(selection.errorMessage, contains('no video clips'));
  });

  test('missing source files are reported without dropping clips', () async {
    await repository.createProject(project);
    final missing = Clip(
      id: 'missing-clip',
      projectId: project.id,
      localPath: '${sources.path}/missing.mp4',
      durationMs: 5000,
      width: 1920,
      height: 1080,
      order: 0,
    );
    await repository.addClip(missing);

    final selection = await service.selectProject(project);

    expect(selection.canOpen, isFalse);
    expect(selection.sourceClips.single.id, missing.id);
    expect(selection.errorMessage, contains(missing.id));
  });

  test(
    'valid legacy path snapshot migrates without removing legacy data',
    () async {
      await repository.createProject(project);
      final clip = await makeClip(
        id: 'first-clip',
        path: '${sources.path}/legacy.mp4',
        order: 0,
      );
      await repository.addClip(clip);
      final legacyClip = VideoClip(
        path: clip.localPath,
        name: 'legacy edit',
        duration: const Duration(seconds: 4),
        sourceStart: const Duration(seconds: 1),
      );
      await store.save(
        projectId: clip.localPath,
        clips: [legacyClip],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 4),
        ),
      );
      final legacyFile = await snapshotFile(clip.localPath);
      final oldBytes = await legacyFile.readAsBytes();

      final selection = await service.selectProject(project);

      expect(selection.canOpen, isTrue);
      expect(selection.timeline!.projectId, project.id);
      expect(selection.timeline!.clips.single.name, legacyClip.name);
      expect(selection.timeline!.clips.single.sourceClipId, clip.id);
      expect(await store.load(project.id), isNotNull);
      expect(await legacyFile.readAsBytes(), oldBytes);
    },
  );

  test(
    'repository errors propagate to the caller for visible error handling',
    () async {
      final signedOutRepository = ProjectRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: false),
      );
      final signedOutService = M5ProjectLibraryService(
        projectRepository: signedOutRepository,
        projectStore: store,
      );

      await expectLater(signedOutService.getProjects(), throwsStateError);
    },
  );
}
