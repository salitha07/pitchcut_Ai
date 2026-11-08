import 'dart:io';

import '../../../data/project_repository.dart';
import '../../../models/clip.dart';
import '../../../models/project.dart';
import 'editor_project_store.dart';
import 'project_clip_adapter.dart';

class M5ProjectSelection {
  const M5ProjectSelection({
    required this.project,
    required this.sourceClips,
    this.timeline,
    this.errorMessage,
  });

  final Project project;
  final List<Clip> sourceClips;
  final ProjectEditorTimeline? timeline;
  final String? errorMessage;

  bool get canOpen => errorMessage == null && timeline != null;
}

/// M5-owned read and selection flow over the shared M2 project repository.
class M5ProjectLibraryService {
  M5ProjectLibraryService({
    required this._projectRepository,
    required this._projectStore,
    this._adapter = const ProjectClipAdapter(),
  });

  final ProjectRepository _projectRepository;
  final EditorProjectStore _projectStore;
  final ProjectClipAdapter _adapter;

  Future<List<Project>> getProjects() => _projectRepository.getProjects();

  Future<M5ProjectSelection> selectProject(Project project) async {
    final clips = await _projectRepository.getClips(project.id);
    if (clips.isEmpty) {
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        errorMessage: 'This project has no video clips to edit.',
      );
    }

    final missingSourceClips = <Clip>[];
    for (final clip in clips) {
      if (clip.localPath.trim().isEmpty ||
          !await File(clip.localPath).exists()) {
        missingSourceClips.add(clip);
      }
    }
    if (missingSourceClips.isNotEmpty) {
      final ids = missingSourceClips.map((clip) => clip.id).join(', ');
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        errorMessage: 'Video files are missing for clip(s): $ids.',
      );
    }

    var timeline = await _adapter.load(
      project: project,
      orderedClips: clips,
      store: _projectStore,
    );
    final recoveryError = timeline.recoveryDiagnostic;
    if (recoveryError != null) {
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        timeline: timeline,
        errorMessage:
            'A saved editor snapshot needs recovery. No data was changed. '
            '$recoveryError',
      );
    }

    final migrationError = timeline.migrationDiagnostic;
    if (timeline.unmatchedItems.isNotEmpty ||
        timeline.duplicateTimelineItemIds.isNotEmpty) {
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        timeline: timeline,
        errorMessage: migrationError ?? 'The saved timeline needs review.',
      );
    }

    final missingTimelineClips = <VideoClipPath>[];
    for (final clip in timeline.clips) {
      if (clip.path.trim().isEmpty || !await File(clip.path).exists()) {
        missingTimelineClips.add(VideoClipPath(clip.path, clip.name));
      }
    }
    if (missingTimelineClips.isNotEmpty) {
      final names = missingTimelineClips.map((clip) => clip.name).join(', ');
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        timeline: timeline,
        errorMessage:
            'Video files are missing from the saved timeline: $names.',
      );
    }

    if (timeline.clips.isEmpty) {
      return M5ProjectSelection(
        project: project,
        sourceClips: clips,
        timeline: timeline,
        errorMessage: 'This project has no editable timeline clips.',
      );
    }

    if (timeline.source == EditorSnapshotSource.legacyPath) {
      try {
        await _adapter.persistValidatedMigration(
          timeline: timeline,
          store: _projectStore,
        );
      } on StateError {
        // Another writer may have created the canonical snapshot after load.
        // Reload and use it if valid; never replace it with stale legacy data.
        timeline = await _adapter.load(
          project: project,
          orderedClips: clips,
          store: _projectStore,
        );
        if (timeline.source != EditorSnapshotSource.canonical) rethrow;
      }
    }

    return M5ProjectSelection(
      project: project,
      sourceClips: List.unmodifiable(clips),
      timeline: timeline,
    );
  }
}

class VideoClipPath {
  const VideoClipPath(this.path, this.name);

  final String path;
  final String name;
}
