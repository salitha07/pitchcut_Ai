import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/video_export_state.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';

void main() {
  late Directory root;
  late Directory sourceDirectory;
  late File original;
  late File exported;
  const projectId = '/recordings/original.mp4';
  final timestamp = DateTime.utc(2026, 11, 7, 12);
  const clip = VideoClip(
    path: '/recordings/original.mp4',
    name: 'original.mp4',
    duration: Duration(seconds: 12),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('editor-project-test-');
    sourceDirectory = Directory('${root.path}/sources')..createSync();
    original = File('${sourceDirectory.path}/original.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    exported = File('${sourceDirectory.path}/export.mp4')
      ..writeAsBytesSync([4, 5, 6, 7]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'saves and reloads export metadata associated with its project',
    () async {
      final store = EditorProjectStore(rootDirectory: root);
      await store.save(
        projectId: projectId,
        clips: const [clip],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 12),
        ),
      );

      final saved = await store.saveExportedVideo(
        projectId: projectId,
        sourcePath: exported.path,
        duration: const Duration(seconds: 9),
        quality: VideoExportQuality.p720,
        exportedAt: timestamp,
      );

      expect(
        await original.exists(),
        isTrue,
        reason: 'Original source is preserved.',
      );
      expect(saved.projectId, projectId);
      expect(saved.duration, const Duration(seconds: 9));
      expect(saved.quality, VideoExportQuality.p720);
      expect(saved.exportedAt, timestamp);
      expect(await File(saved.filePath).readAsBytes(), [4, 5, 6, 7]);

      final restartedStore = EditorProjectStore(rootDirectory: root);
      final reloaded = await restartedStore.load(projectId);
      expect(reloaded, isNotNull);
      expect(reloaded!.clips.single.path, clip.path);
      expect(reloaded.exports.single.filePath, saved.filePath);
      expect(reloaded.exports.single.projectId, projectId);
      expect(await restartedStore.load('/different/project'), isNull);
      expect(await restartedStore.listProjectIds(), [projectId]);
    },
  );

  test(
    'missing export does not create a project record or partial video',
    () async {
      final store = EditorProjectStore(rootDirectory: root);
      await expectLater(
        store.saveExportedVideo(
          projectId: projectId,
          sourcePath: '${sourceDirectory.path}/missing.mp4',
          duration: const Duration(seconds: 9),
          quality: VideoExportQuality.p480,
          exportedAt: timestamp,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.load(projectId), isNull);
      final exports = Directory('${root.path}/project_exports');
      expect(await exports.exists(), isFalse);
    },
  );

  test('empty snapshot is reported as invalid rather than missing', () async {
    final store = EditorProjectStore(rootDirectory: root);
    final snapshot = await _snapshotFile(root, projectId);
    await snapshot.parent.create(recursive: true);
    await snapshot.writeAsString('');

    await expectLater(
      store.load(projectId),
      throwsA(
        isA<InvalidEditorSnapshotException>().having(
          (error) => error.projectId,
          'projectId',
          projectId,
        ),
      ),
    );
    expect(await snapshot.readAsString(), isEmpty);
  });

  test(
    'truncated JSON snapshot is reported as invalid and preserved',
    () async {
      final store = EditorProjectStore(rootDirectory: root);
      final snapshot = await _snapshotFile(root, projectId);
      await snapshot.parent.create(recursive: true);
      const malformed = '{"clips":[{"path":';
      await snapshot.writeAsString(malformed);

      await expectLater(
        store.load(projectId),
        throwsA(isA<InvalidEditorSnapshotException>()),
      );
      expect(await snapshot.readAsString(), malformed);
    },
  );

  test(
    'save with explicit exports does not replace an invalid snapshot',
    () async {
      final store = EditorProjectStore(rootDirectory: root);
      final snapshot = await _snapshotFile(root, projectId);
      await snapshot.parent.create(recursive: true);
      const malformed = '{"clips":';
      await snapshot.writeAsString(malformed);

      await expectLater(
        store.save(
          projectId: projectId,
          clips: const [clip],
          selectedClipIndex: 0,
          trimRange: const TrimRange(
            start: Duration.zero,
            end: Duration(seconds: 12),
          ),
          exports: const [],
        ),
        throwsA(isA<InvalidEditorSnapshotException>()),
      );
      expect(await snapshot.readAsString(), malformed);
    },
  );

  test('metadata write failure rolls back the copied video', () async {
    File('${root.path}/editor_projects').writeAsStringSync('not a directory');
    final store = EditorProjectStore(rootDirectory: root);

    await expectLater(
      store.saveExportedVideo(
        projectId: projectId,
        sourcePath: exported.path,
        duration: const Duration(seconds: 9),
        quality: VideoExportQuality.p1080,
        exportedAt: timestamp,
      ),
      throwsA(anything),
    );

    final projectExports = Directory('${root.path}/project_exports');
    final files = await projectExports
        .list(recursive: true)
        .where((entry) => entry is File)
        .toList();
    expect(files, isEmpty);
  });
}

Future<File> _snapshotFile(Directory root, String projectId) async {
  final safeId = base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
  return File('${root.path}/editor_projects/$safeId.json');
}
