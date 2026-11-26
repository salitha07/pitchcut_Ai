import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/video_export_state.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/services/project_clip_adapter.dart';
import 'package:pitchcut_ai/features/editor/services/timeline_operations.dart';
import 'package:pitchcut_ai/models/clip.dart';
import 'package:pitchcut_ai/models/project.dart';

void main() {
  late Directory root;
  late EditorProjectStore store;
  const project = Project(
    id: 'project-canonical-1',
    userId: 'user-1',
    title: 'Practice',
    createdAt: '2026-11-01T00:00:00.000Z',
    updatedAt: '2026-11-01T00:00:00.000Z',
    clipIds: ['clip-later', 'clip-first'],
  );
  const first = Clip(
    id: 'clip-first',
    projectId: 'project-canonical-1',
    localPath: '/videos/first.mp4',
    durationMs: 10000,
    width: 1920,
    height: 1080,
    order: 0,
  );
  const later = Clip(
    id: 'clip-later',
    projectId: 'project-canonical-1',
    localPath: '/videos/later.mp4',
    durationMs: 8000,
    width: 1280,
    height: 720,
    order: 1,
  );
  const adapter = ProjectClipAdapter();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('project-clip-adapter-');
    store = EditorProjectStore(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'maps canonical project and source clip identities in timeline order',
    () {
      final mapped = adapter.fromProject(
        project: project,
        orderedClips: const [later, first],
      );

      expect(mapped.map((clip) => clip.path), [
        first.localPath,
        later.localPath,
      ]);
      expect(mapped.map((clip) => clip.sourceClipId), [first.id, later.id]);
      expect(mapped.first.timelineItemId, isNotEmpty);
      expect(mapped.first.path, first.localPath);
      expect(mapped.first.sourceDuration, const Duration(seconds: 10));
    },
  );

  test('split timeline segments keep source identity and get distinct IDs', () {
    final source = adapter
        .fromProject(project: project, orderedClips: const [first])
        .single;
    final split = TimelineOperations.split(
      [source],
      0,
      const Duration(seconds: 4),
    );

    expect(split.map((clip) => clip.sourceClipId), [first.id, first.id]);
    expect(split.first.timelineItemId, isNot(split.last.timelineItemId));
    expect(split.first.path, split.last.path);
    expect(split.last.sourceStart, const Duration(seconds: 4));
  });

  test(
    'canonical Project.id snapshot takes precedence over legacy path',
    () async {
      const canonicalClip = VideoClip(
        path: '/videos/first.mp4',
        name: 'canonical edit',
        duration: Duration(seconds: 10),
        sourceClipId: 'clip-first',
        timelineItemId: 'canonical-item',
      );
      const legacyClip = VideoClip(
        path: '/videos/first.mp4',
        name: 'legacy edit',
        duration: Duration(seconds: 10),
      );
      await store.save(
        projectId: 'project-canonical-1',
        clips: const [canonicalClip],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 10),
        ),
      );
      await store.save(
        projectId: first.localPath,
        clips: const [legacyClip],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration(seconds: 2),
          end: Duration(seconds: 8),
        ),
      );

      final loaded = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      expect(loaded.source, EditorSnapshotSource.canonical);
      expect(loaded.projectId, project.id);
      expect(loaded.clips.single.name, 'canonical edit');
      expect(loaded.clips.single.timelineItemId, 'canonical-item');
    },
  );

  test('empty canonical snapshot has an explicit recovery status', () async {
    final canonicalFile = await _snapshotFile(root, project.id);
    await canonicalFile.parent.create(recursive: true);
    await canonicalFile.writeAsString('');

    final recovered = await adapter.load(
      project: project,
      orderedClips: const [first],
      store: store,
    );

    expect(recovered.source, EditorSnapshotSource.invalidCanonical);
    expect(recovered.clips, isEmpty);
    expect(recovered.canonicalError, isNotNull);
    expect(recovered.recoveryDiagnostic, contains('Invalid editor snapshot'));
    expect(await canonicalFile.readAsString(), isEmpty);
    expect(recovered.canPersistMigration, isFalse);
  });

  test('invalid canonical snapshot allows read-only legacy fallback without changes', () async {
    const legacy = VideoClip(
      path: '/videos/first.mp4',
      name: 'recoverable legacy edit',
      duration: Duration(seconds: 8),
      sourceStart: Duration(seconds: 1),
      rotationDegrees: 180,
    );
    await store.save(
      projectId: first.localPath,
      clips: const [legacy],
      selectedClipIndex: 0,
      trimRange: const TrimRange(
        start: Duration.zero,
        end: Duration(seconds: 8),
      ),
    );
    final exportSource = File('${root.path}/recovery-export.mp4')
      ..writeAsBytesSync([21, 22, 23]);
    final savedExport = await store.saveExportedVideo(
      projectId: first.localPath,
      sourcePath: exportSource.path,
      duration: const Duration(seconds: 8),
      quality: VideoExportQuality.p720,
      exportedAt: DateTime.utc(2026, 11, 5),
    );
    final canonicalFile = await _snapshotFile(root, project.id);
    await canonicalFile.writeAsString('{"clips":[', flush: true);
    final canonicalBytes = await canonicalFile.readAsBytes();
    final legacyFile = await _snapshotFile(root, first.localPath);
    final legacyBytes = await legacyFile.readAsBytes();
    final exportFile = File(savedExport.filePath);
    final exportBytes = await exportFile.readAsBytes();

    final recovered = await adapter.load(
      project: project,
      orderedClips: const [first],
      store: store,
    );

    expect(
      recovered.source,
      EditorSnapshotSource.invalidCanonicalLegacyFallback,
    );
    expect(recovered.canonicalError, isNotNull);
    expect(recovered.clips.single.name, legacy.name);
    expect(recovered.clips.single.sourceStart, legacy.sourceStart);
    expect(recovered.clips.single.rotationDegrees, legacy.rotationDegrees);
    expect(recovered.exports.single.filePath, savedExport.filePath);
    expect(recovered.canPersistMigration, isFalse);
    await expectLater(
      adapter.persistValidatedMigration(timeline: recovered, store: store),
      throwsStateError,
    );

    expect(await canonicalFile.readAsBytes(), canonicalBytes);
    expect(await legacyFile.readAsBytes(), legacyBytes);
    expect(await exportFile.readAsBytes(), exportBytes);
  });

  test(
    'legacy read-through preserves edits and exports without writing',
    () async {
      const legacy = VideoClip(
        path: '/videos/first.mp4',
        name: 'trimmed and rotated',
        duration: Duration(seconds: 6),
        sourceStart: Duration(seconds: 2),
        sourceDuration: Duration(seconds: 10),
        rotationDegrees: 90,
        crop: CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
      );
      await store.save(
        projectId: first.localPath,
        clips: const [legacy],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration(milliseconds: 500),
          end: Duration(seconds: 5),
        ),
      );
      final source = File('${root.path}/export.mp4')
        ..writeAsBytesSync([1, 2, 3]);
      final savedExport = await store.saveExportedVideo(
        projectId: first.localPath,
        sourcePath: source.path,
        duration: const Duration(seconds: 6),
        quality: VideoExportQuality.p720,
        exportedAt: DateTime.utc(2026, 11, 2),
      );
      final legacyFileBefore = await _snapshotFile(root, first.localPath);
      final legacyBytesBefore = await legacyFileBefore.readAsBytes();

      final loaded = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      expect(loaded.source, EditorSnapshotSource.legacyPath);
      expect(loaded.projectId, project.id);
      expect(loaded.clips.single.sourceClipId, first.id);
      expect(loaded.clips.single.name, legacy.name);
      expect(loaded.clips.single.sourceStart, legacy.sourceStart);
      expect(loaded.clips.single.rotationDegrees, 90);
      expect(loaded.clips.single.crop, legacy.crop);
      expect(loaded.trimRange.start, const Duration(milliseconds: 500));
      expect(loaded.exports.single.filePath, savedExport.filePath);
      expect(loaded.exports.single.projectId, project.id);
      expect(await store.load(project.id), isNull);
      expect(await legacyFileBefore.readAsBytes(), legacyBytesBefore);
    },
  );

  test(
    'validated migration writes canonical copy and leaves legacy file',
    () async {
      const legacy = VideoClip(
        path: '/videos/first.mp4',
        name: 'edited',
        duration: Duration(seconds: 7),
        sourceStart: Duration(seconds: 1),
      );
      await store.save(
        projectId: first.localPath,
        clips: const [legacy],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 7),
        ),
      );
      final exportSource = File('${root.path}/export.mp4')
        ..writeAsBytesSync([8, 9, 10]);
      final savedExport = await store.saveExportedVideo(
        projectId: first.localPath,
        sourcePath: exportSource.path,
        duration: const Duration(seconds: 7),
        quality: VideoExportQuality.p1080,
        exportedAt: DateTime.utc(2026, 11, 3),
      );
      final legacyFile = await _snapshotFile(root, first.localPath);
      final legacyBytes = await legacyFile.readAsBytes();
      final loaded = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      await adapter.persistValidatedMigration(timeline: loaded, store: store);

      expect(await store.load(project.id), isNotNull);
      expect(await legacyFile.exists(), isTrue);
      expect(await legacyFile.readAsBytes(), legacyBytes);
      final migrated = (await store.load(project.id))!;
      expect(migrated.clips.single.name, 'edited');
      expect(migrated.exports.single.filePath, savedExport.filePath);
      expect(migrated.exports.single.projectId, project.id);
      expect(await File(savedExport.filePath).readAsBytes(), [8, 9, 10]);
    },
  );

  test(
    'unmatched legacy items remain visible and block migration writes',
    () async {
      const unmatched = VideoClip(
        path: '/videos/missing-from-m2.mp4',
        name: 'unmatched',
        duration: Duration(seconds: 5),
        sourceStart: Duration(seconds: 2),
        rotationDegrees: 180,
      );
      await store.save(
        projectId: first.localPath,
        clips: const [unmatched],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 5),
        ),
      );

      final loaded = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      expect(loaded.clips.single.path, unmatched.path);
      expect(loaded.clips.single.rotationDegrees, 180);
      expect(loaded.clips.single.sourceClipId, isNull);
      expect(loaded.unmatchedItems, [
        isA<UnmatchedTimelineItem>()
            .having((item) => item.index, 'index', 0)
            .having((item) => item.path, 'path', unmatched.path),
      ]);
      expect(loaded.canPersistMigration, isFalse);
      await expectLater(
        adapter.persistValidatedMigration(timeline: loaded, store: store),
        throwsStateError,
      );
      expect(await store.load(project.id), isNull);
    },
  );

  test(
    'migration refuses to overwrite a canonical snapshot created later',
    () async {
      await store.save(
        projectId: first.localPath,
        clips: const [
          VideoClip(
            path: '/videos/first.mp4',
            name: 'legacy',
            duration: Duration(seconds: 10),
          ),
        ],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 10),
        ),
      );
      final legacy = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );
      await store.save(
        projectId: 'project-canonical-1',
        clips: const [
          VideoClip(
            path: '/videos/first.mp4',
            name: 'newer canonical',
            duration: Duration(seconds: 10),
          ),
        ],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 10),
        ),
      );

      await expectLater(
        adapter.persistValidatedMigration(timeline: legacy, store: store),
        throwsStateError,
      );
      expect(
        (await store.load(project.id))!.clips.single.name,
        'newer canonical',
      );
    },
  );

  test(
    'concurrent migration attempts allow exactly one canonical create',
    () async {
      await store.save(
        projectId: first.localPath,
        clips: const [
          VideoClip(
            path: '/videos/first.mp4',
            name: 'legacy',
            duration: Duration(seconds: 10),
          ),
        ],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 10),
        ),
      );
      final legacy = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          () async {
            try {
              await adapter.persistValidatedMigration(
                timeline: legacy,
                store: store,
              );
              return true;
            } on StateError {
              return false;
            }
          }(),
      ]);

      expect(results.where((success) => success), hasLength(1));
      expect(results.where((success) => !success), hasLength(1));
      expect((await store.load(project.id))!.clips.single.name, 'legacy');
    },
  );

  test(
    'duplicate timeline IDs block migration without changing legacy data',
    () async {
      const duplicateOne = VideoClip(
        path: '/videos/first.mp4',
        name: 'segment one',
        duration: Duration(seconds: 4),
        sourceClipId: 'clip-first',
        timelineItemId: 'duplicate-item-id',
      );
      const duplicateTwo = VideoClip(
        path: '/videos/first.mp4',
        name: 'segment two',
        duration: Duration(seconds: 6),
        sourceStart: Duration(seconds: 4),
        sourceClipId: 'clip-first',
        timelineItemId: 'duplicate-item-id',
      );
      await store.save(
        projectId: first.localPath,
        clips: const [duplicateOne, duplicateTwo],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 4),
        ),
      );
      final exportSource = File('${root.path}/export.mp4')
        ..writeAsBytesSync([11, 12, 13]);
      final savedExport = await store.saveExportedVideo(
        projectId: first.localPath,
        sourcePath: exportSource.path,
        duration: const Duration(seconds: 10),
        quality: VideoExportQuality.p720,
        exportedAt: DateTime.utc(2026, 11, 4),
      );
      final legacyFile = await _snapshotFile(root, first.localPath);
      final legacyBytes = await legacyFile.readAsBytes();
      final exportBytes = await File(savedExport.filePath).readAsBytes();

      final loaded = await adapter.load(
        project: project,
        orderedClips: const [first],
        store: store,
      );

      expect(loaded.duplicateTimelineItemIds, ['duplicate-item-id']);
      expect(
        loaded.migrationDiagnostic,
        contains('duplicate timeline item IDs'),
      );
      expect(loaded.canPersistMigration, isFalse);
      await expectLater(
        adapter.persistValidatedMigration(timeline: loaded, store: store),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'diagnostic',
            contains('duplicate-item-id'),
          ),
        ),
      );

      expect(await store.load(project.id), isNull);
      expect(await legacyFile.readAsBytes(), legacyBytes);
      expect(await File(savedExport.filePath).readAsBytes(), exportBytes);
    },
  );

  test('rejects clip records belonging to another project', () {
    expect(
      () => adapter.fromProject(
        project: project,
        orderedClips: [first.copyWith(projectId: 'other-project')],
      ),
      throwsArgumentError,
    );
  });
}

Future<File> _snapshotFile(Directory root, String projectId) async {
  final encoded = base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
  return File('${root.path}/editor_projects/$encoded.json');
}
