import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/project_repository.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/services/m5_project_library_service.dart';
import 'package:pitchcut_ai/features/editor/services/m5_video_import_service.dart';
import 'package:pitchcut_ai/features/editor/services/project_clip_adapter.dart';
import 'package:pitchcut_ai/features/editor/services/video_trim_service.dart';
import 'package:pitchcut_ai/features/editor/video_editor_library_screen.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';
import 'package:pitchcut_ai/models/clip.dart' as m2;
import 'package:pitchcut_ai/models/project.dart';
import 'package:pitchcut_ai/providers/repository_providers.dart';
// video_player exports the player value types but not its platform test seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late MemoryEditorProjectStore store;
  late FakeVideoPlayerPlatform videoPlatform;
  late FakeM5ProjectLibraryService projectLibrary;
  late FakeM5VideoImporter videoImporter;
  late ProjectRepository repository;
  late List<PlatformFile> pickedFiles;
  late int pickerCalls;

  const project = Project(
    id: 'shared-project-ui',
    userId: 'ui-user',
    title: 'Shared M2 project',
    createdAt: '2026-11-08T00:00:00.000Z',
    updatedAt: '2026-11-08T00:00:00.000Z',
    clipIds: ['clip-second', 'clip-first'],
  );

  late List<m2.Clip> orderedClips;
  late ProjectEditorTimeline timeline;
  late List<Project> listedProjects;
  late M5ProjectSelection Function(Project project) selectionBuilder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('m5-library-widget-');
    final firstPath = '${root.path}/first.mp4';
    final secondPath = '${root.path}/second.mp4';
    orderedClips = [
      m2.Clip(
        id: 'clip-first',
        projectId: project.id,
        localPath: firstPath,
        durationMs: 5000,
        width: 1920,
        height: 1080,
        order: 0,
      ),
      m2.Clip(
        id: 'clip-second',
        projectId: project.id,
        localPath: secondPath,
        durationMs: 5000,
        width: 1920,
        height: 1080,
        order: 1,
      ),
    ];
    final adapted = const ProjectClipAdapter().fromProject(
      project: project,
      orderedClips: orderedClips,
    );
    timeline = ProjectEditorTimeline(
      projectId: project.id,
      clips: adapted,
      selectedClipIndex: 0,
      trimRange: const TrimRange(
        start: Duration.zero,
        end: Duration(seconds: 5),
      ),
      exports: const [],
      source: EditorSnapshotSource.empty,
      unmatchedItems: const [],
    );
    listedProjects = [project];
    pickedFiles = [];
    pickerCalls = 0;
    store = MemoryEditorProjectStore();
    videoPlatform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
    repository = ProjectRepository(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'ui-user'),
      ),
    );
    projectLibrary = FakeM5ProjectLibraryService(
      repository: repository,
      store: store,
      projects: () => listedProjects,
      selection: (selected) => selectionBuilder(selected),
    );
    selectionBuilder = (selected) => M5ProjectSelection(
      project: selected,
      sourceClips: orderedClips,
      timeline: timeline,
    );
    videoImporter = FakeM5VideoImporter(project);
  });

  tearDown(() async {
    VideoPlayerPlatform.instance = _previousVideoPlatform;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Widget library() => ProviderScope(
    overrides: [projectRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: VideoEditorLibraryScreen(
        projectStore: store,
        trimService: FakeVideoTrimService(),
        projectLibrary: projectLibrary,
        videoImportService: videoImporter,
        videoPicker: () async {
          pickerCalls++;
          return pickedFiles;
        },
        fileExists: (_) async => true,
      ),
    ),
  );

  testWidgets('lists M2 projects and retains legacy entry points', (
    tester,
  ) async {
    final legacyId = '${root.path}/legacy/old.mp4';
    store.seed(
      legacyId,
      EditorProjectSnapshot(
        clips: [
          VideoClip(
            path: legacyId,
            name: 'old.mp4',
            duration: Duration(seconds: 5),
          ),
        ],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 5),
        ),
      ),
    );

    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    expect(find.text('Shared M2 project'), findsOneWidget);
    expect(find.text('Open a video'), findsOneWidget);
    expect(find.text('Saved editor projects'), findsOneWidget);
    expect(find.text('old.mp4'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Open a video'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'shared project opens without writing, then first edit persists identities',
    (tester) async {
      await tester.pumpWidget(library());
      await _pumpFrames(tester);

      await tester.tap(find.text('Shared M2 project'));
      await _pumpFrames(tester);

      expect(find.byType(VideoEditorScreen), findsOneWidget);
      expect(projectLibrary.selectedProject?.id, project.id);
      expect(store.saveCalls, 0);
      expect(await store.load(project.id), isNull);
      final rotateButton = find.byKey(const ValueKey('rotate-selected-clip'));
      expect(rotateButton, findsOneWidget);
      expect(tester.widget<OutlinedButton>(rotateButton).onPressed, isNotNull);

      await tester.ensureVisible(rotateButton);
      await tester.tap(rotateButton);
      await _pumpFrames(tester);

      expect(find.text('Rotate 180°'), findsOneWidget);
      expect(store.saveCalls, 1);
      final saved = await store.load(project.id);
      expect(saved, isNotNull);
      expect(saved!.clips.map((clip) => clip.sourceClipId), [
        'clip-first',
        'clip-second',
      ]);
      expect(saved.clips.map((clip) => clip.timelineItemId), [
        timeline.clips[0].timelineItemId,
        timeline.clips[1].timelineItemId,
      ]);
      expect(saved.clips.first.rotationDegrees, 90);
    },
  );

  testWidgets('opening an existing canonical snapshot leaves it unchanged', (
    tester,
  ) async {
    final originalClips = timeline.clips
        .map((clip) => clip.copyWith(rotationDegrees: 180))
        .toList(growable: false);
    final original = EditorProjectSnapshot(
      clips: originalClips,
      selectedClipIndex: 1,
      trimRange: const TrimRange(
        start: Duration(seconds: 1),
        end: Duration(seconds: 4),
      ),
    );
    store.seed(project.id, original);
    timeline = ProjectEditorTimeline(
      projectId: project.id,
      clips: original.clips,
      selectedClipIndex: original.selectedClipIndex,
      trimRange: original.trimRange,
      exports: original.exports,
      source: EditorSnapshotSource.canonical,
      unmatchedItems: const [],
    );

    await tester.pumpWidget(library());
    await _pumpFrames(tester);
    await tester.tap(find.text(project.title));
    await _pumpFrames(tester);

    expect(find.byType(VideoEditorScreen), findsOneWidget);
    expect(store.saveCalls, 0);
    final afterOpen = await store.load(project.id);
    expect(afterOpen?.clips.map((clip) => clip.rotationDegrees), [180, 180]);
    expect(afterOpen?.selectedClipIndex, 1);
    expect(afterOpen?.trimRange, original.trimRange);
  });

  testWidgets('legacy saved-project tile remains openable', (tester) async {
    final legacyId = '${root.path}/legacy/old.mp4';
    store.seed(
      legacyId,
      EditorProjectSnapshot(
        clips: [
          VideoClip(
            path: legacyId,
            name: 'old.mp4',
            duration: Duration(seconds: 5),
          ),
        ],
        selectedClipIndex: 0,
        trimRange: const TrimRange(
          start: Duration.zero,
          end: Duration(seconds: 5),
        ),
      ),
    );
    await tester.pumpWidget(library());
    await _pumpFrames(tester);
    await tester.tap(find.text('old.mp4'));
    await _pumpFrames(tester);

    expect(find.byType(VideoEditorScreen), findsOneWidget);
    expect(store.loadCalls, contains(legacyId));
  });

  testWidgets('picker cancellation leaves the library unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);

    expect(pickerCalls, 1);
    expect(videoImporter.calls, 0);
    expect(find.byType(VideoEditorScreen), findsNothing);
    expect(find.text('Shared M2 project'), findsOneWidget);
  });

  testWidgets('busy state prevents duplicate picker requests', (tester) async {
    final pendingPicker = Completer<List<PlatformFile>>();
    projectLibrary.selectedProject = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [projectRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: VideoEditorLibraryScreen(
            projectStore: store,
            trimService: FakeVideoTrimService(),
            projectLibrary: projectLibrary,
            videoImportService: videoImporter,
            videoPicker: () {
              pickerCalls++;
              return pendingPicker.future;
            },
            fileExists: (_) async => true,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);
    expect(find.text('Importing video…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    expect(pickerCalls, 1);

    pendingPicker.complete([]);
    await _pumpFrames(tester);
    expect(find.text('Open a video'), findsOneWidget);
    expect(videoImporter.calls, 0);
  });

  testWidgets('busy state covers M3 save and M2 clip loading', (tester) async {
    pickedFiles = [TestPlatformFile('picked.mp4', '${root.path}/picked.mp4')];
    videoImporter.pendingResult = Completer<Project>();
    projectLibrary.pendingSelection = Completer<M5ProjectSelection>();
    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await _pumpFrames(tester);
    expect(find.text('Importing video…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );

    videoImporter.pendingResult!.complete(project);
    await _pumpFrames(tester);
    expect(projectLibrary.selectedProject?.id, project.id);
    expect(find.text('Importing video…'), findsOneWidget);
    expect(find.byType(VideoEditorScreen), findsNothing);

    projectLibrary.pendingSelection!.complete(
      M5ProjectSelection(
        project: project,
        sourceClips: orderedClips,
        timeline: timeline,
      ),
    );
    await _pumpFrames(tester);
    expect(find.byType(VideoEditorScreen), findsOneWidget);
  });

  testWidgets('successful M3 import loads M2 clips before navigation', (
    tester,
  ) async {
    pickedFiles = [
      TestPlatformFile('picked-match.mp4', '${root.path}/picked.mp4'),
    ];
    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);
    expect(find.text('Save Imported Video'), findsOneWidget);
    expect(find.text('picked-match'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await _pumpFrames(tester);

    expect(videoImporter.calls, 1);
    expect(
      videoImporter.video?.path.replaceAll('\\', '/'),
      '${root.path}/picked.mp4'.replaceAll('\\', '/'),
    );
    expect(videoImporter.title, 'picked-match');
    expect(projectLibrary.selectedProject?.id, project.id);
    expect(find.byType(VideoEditorScreen), findsOneWidget);
    expect(store.saveCalls, 0);
  });

  testWidgets('ambiguous M3 write failure is not retried and refreshes list', (
    tester,
  ) async {
    pickedFiles = [TestPlatformFile('picked.mp4', '${root.path}/picked.mp4')];
    videoImporter.failure = StateError(
      'Unable to complete Firebase project saving. Project ID: partial-id.',
    );
    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await _pumpFrames(tester);

    expect(videoImporter.calls, 1);
    expect(find.byType(VideoEditorScreen), findsNothing);
    expect(find.textContaining('No retry was made'), findsOneWidget);
    expect(projectLibrary.getProjectsCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('post-import clip lookup failure does not navigate', (
    tester,
  ) async {
    pickedFiles = [TestPlatformFile('picked.mp4', '${root.path}/picked.mp4')];
    selectionBuilder = (selected) => M5ProjectSelection(
      project: selected,
      sourceClips: const [],
      errorMessage: 'Project has no clips yet.',
    );
    await tester.pumpWidget(library());
    await _pumpFrames(tester);

    await tester.tap(find.text('Open a video'));
    await _pumpFrames(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await _pumpFrames(tester);

    expect(videoImporter.calls, 1);
    expect(projectLibrary.selectedProject?.id, project.id);
    expect(find.byType(VideoEditorScreen), findsNothing);
    expect(
      find.textContaining('The project remains in your library.'),
      findsOneWidget,
    );
    expect(projectLibrary.getProjectsCalls, greaterThanOrEqualTo(2));
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Pump bounded frames instead of waiting for progress-indicator animations.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump();
  }
}

final VideoPlayerPlatform _previousVideoPlatform = VideoPlayerPlatform.instance;

class FakeM5ProjectLibraryService extends M5ProjectLibraryService {
  FakeM5ProjectLibraryService({
    required ProjectRepository repository,
    required EditorProjectStore store,
    required this.projects,
    required this.selection,
  }) : super(projectRepository: repository, projectStore: store);

  final List<Project> Function() projects;
  final M5ProjectSelection Function(Project project) selection;
  Project? selectedProject;
  int getProjectsCalls = 0;
  Completer<M5ProjectSelection>? pendingSelection;

  @override
  Future<List<Project>> getProjects() async {
    getProjectsCalls++;
    return projects();
  }

  @override
  Future<M5ProjectSelection> selectProject(Project project) async {
    selectedProject = project;
    final pending = pendingSelection;
    if (pending != null) return pending.future;
    return selection(project);
  }
}

class FakeM5VideoImporter implements M5VideoImporter {
  FakeM5VideoImporter(this.result);

  final Project result;
  int calls = 0;
  XFile? video;
  String? title;
  Object? failure;
  Completer<Project>? pendingResult;

  @override
  Future<Project> importVideo({
    required XFile video,
    required String title,
  }) async {
    calls++;
    this.video = video;
    this.title = title;
    if (failure case final error?) throw error;
    final pending = pendingResult;
    if (pending != null) return pending.future;
    return result;
  }
}

base class TestPlatformFile extends PlatformFile {
  TestPlatformFile(this.name, this._path);

  @override
  final String name;
  final String _path;

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path, name: name);

  @override
  int? lengthSync() => 5;

  @override
  Future<int?> length() async => 5;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3, 4, 5]);

  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList([1, 2, 3, 4, 5]));
}

class MemoryEditorProjectStore extends EditorProjectStore {
  MemoryEditorProjectStore() : super();

  final Map<String, EditorProjectSnapshot> _snapshots = {};
  final List<String> loadCalls = [];
  int saveCalls = 0;

  void seed(String projectId, EditorProjectSnapshot snapshot) {
    _snapshots[projectId] = snapshot;
  }

  @override
  Future<List<String>> listProjectIds() async => _snapshots.keys.toList();

  @override
  Future<EditorProjectSnapshot?> load(String projectId) async {
    loadCalls.add(projectId);
    return _snapshots[projectId];
  }

  @override
  Future<void> save({
    required String projectId,
    required List<VideoClip> clips,
    required int selectedClipIndex,
    required TrimRange trimRange,
    List<SavedExport>? exports,
  }) async {
    saveCalls++;
    _snapshots[projectId] = EditorProjectSnapshot(
      clips: List.unmodifiable(clips),
      selectedClipIndex: selectedClipIndex,
      trimRange: trimRange,
      exports: exports ?? _snapshots[projectId]?.exports ?? const [],
    );
  }
}

class FakeVideoTrimService extends VideoTrimService {
  @override
  Future<Uint8List?> generateThumbnail(
    String inputPath, {
    Duration time = Duration.zero,
  }) async => null;
}

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  var _nextId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _nextId++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1920, 1080),
    ),
  );

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.shrink();
}
