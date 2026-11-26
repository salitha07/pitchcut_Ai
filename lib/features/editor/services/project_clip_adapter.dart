import 'dart:convert';

import '../../../models/clip.dart' as m2;
import '../../../models/project.dart' as m2;
import '../models/trim_range.dart';
import '../models/video_clip.dart';
import 'editor_project_store.dart';

enum EditorSnapshotSource {
  canonical,
  legacyPath,
  empty,
  invalidCanonical,
  invalidCanonicalLegacyFallback,
  invalidLegacy,
}

class UnmatchedTimelineItem {
  const UnmatchedTimelineItem({required this.index, required this.path});

  final int index;
  final String path;
}

class ProjectEditorTimeline {
  const ProjectEditorTimeline({
    required this.projectId,
    required this.clips,
    required this.selectedClipIndex,
    required this.trimRange,
    required this.exports,
    required this.source,
    required this.unmatchedItems,
    this.duplicateTimelineItemIds = const [],
    this.legacyPath,
    this.canonicalError,
    this.legacyError,
  });

  final String projectId;
  final List<VideoClip> clips;
  final int selectedClipIndex;
  final TrimRange trimRange;
  final List<SavedExport> exports;
  final EditorSnapshotSource source;
  final List<UnmatchedTimelineItem> unmatchedItems;
  final List<String> duplicateTimelineItemIds;
  final String? legacyPath;
  final InvalidEditorSnapshotException? canonicalError;
  final InvalidEditorSnapshotException? legacyError;

  bool get canPersistMigration =>
      source == EditorSnapshotSource.legacyPath &&
      unmatchedItems.isEmpty &&
      duplicateTimelineItemIds.isEmpty;

  String? get migrationDiagnostic {
    if (unmatchedItems.isNotEmpty) {
      return 'Cannot migrate: ${unmatchedItems.length} timeline item(s) do not map to M2 clips.';
    }
    if (duplicateTimelineItemIds.isNotEmpty) {
      return 'Cannot migrate: duplicate timeline item IDs: '
          '${duplicateTimelineItemIds.join(', ')}.';
    }
    return null;
  }

  String? get recoveryDiagnostic {
    final errors = [
      if (canonicalError != null) canonicalError.toString(),
      if (legacyError != null) legacyError.toString(),
    ];
    return errors.isEmpty ? null : errors.join('\n');
  }
}

/// M5-only translation between M2 source records and M5 editable timeline state.
class ProjectClipAdapter {
  const ProjectClipAdapter();

  List<VideoClip> fromProject({
    required m2.Project project,
    required List<m2.Clip> orderedClips,
  }) {
    final clips = _validateAndSort(project, orderedClips);
    return List.unmodifiable(
      clips.map((clip) {
        final timelineId = _timelineId(project.id, clip.id, 0, clip.durationMs);
        return VideoClip(
          path: clip.localPath,
          name: _fileName(clip.localPath),
          duration: Duration(milliseconds: clip.durationMs),
          sourceDuration: Duration(milliseconds: clip.durationMs),
          sourceClipId: clip.id,
          timelineItemId: timelineId,
        );
      }),
    );
  }

  /// Loads a canonical Project.id snapshot first, then reads the old path key.
  /// A legacy result is never written here; call [persistValidatedMigration]
  /// after reviewing its unmatchedItems.
  Future<ProjectEditorTimeline> load({
    required m2.Project project,
    required List<m2.Clip> orderedClips,
    required EditorProjectStore store,
  }) async {
    final sources = _validateAndSort(project, orderedClips);
    EditorProjectSnapshot? canonical;
    InvalidEditorSnapshotException? canonicalError;
    try {
      canonical = await store.load(project.id);
    } on InvalidEditorSnapshotException catch (error) {
      canonicalError = error;
    }
    if (canonical != null) {
      return _mapSnapshot(
        project: project,
        sources: sources,
        snapshot: canonical,
        source: EditorSnapshotSource.canonical,
      );
    }

    if (sources.isEmpty) {
      return ProjectEditorTimeline(
        projectId: project.id,
        clips: const [],
        selectedClipIndex: 0,
        trimRange: const TrimRange(start: Duration.zero, end: Duration.zero),
        exports: const [],
        source: canonicalError == null
            ? EditorSnapshotSource.empty
            : EditorSnapshotSource.invalidCanonical,
        unmatchedItems: const [],
        canonicalError: canonicalError,
      );
    }

    final legacyPath = sources.first.localPath;
    EditorProjectSnapshot? legacy;
    InvalidEditorSnapshotException? legacyError;
    try {
      legacy = await store.load(legacyPath);
    } on InvalidEditorSnapshotException catch (error) {
      legacyError = error;
    }
    if (legacy == null) {
      if (canonicalError != null || legacyError != null) {
        return ProjectEditorTimeline(
          projectId: project.id,
          clips: const [],
          selectedClipIndex: 0,
          trimRange: const TrimRange(start: Duration.zero, end: Duration.zero),
          exports: const [],
          source: canonicalError != null
              ? EditorSnapshotSource.invalidCanonical
              : EditorSnapshotSource.invalidLegacy,
          unmatchedItems: const [],
          canonicalError: canonicalError,
          legacyError: legacyError,
          legacyPath: legacyPath,
        );
      }
      return ProjectEditorTimeline(
        projectId: project.id,
        clips: fromProject(project: project, orderedClips: sources),
        selectedClipIndex: 0,
        trimRange: TrimRange(
          start: Duration.zero,
          end: Duration(milliseconds: sources.first.durationMs),
        ),
        exports: const [],
        source: EditorSnapshotSource.empty,
        unmatchedItems: const [],
      );
    }
    return _mapSnapshot(
      project: project,
      sources: sources,
      snapshot: legacy,
      source: canonicalError == null
          ? EditorSnapshotSource.legacyPath
          : EditorSnapshotSource.invalidCanonicalLegacyFallback,
      legacyPath: legacyPath,
      canonicalError: canonicalError,
    );
  }

  Future<void> persistValidatedMigration({
    required ProjectEditorTimeline timeline,
    required EditorProjectStore store,
  }) async {
    if (!timeline.canPersistMigration) {
      throw StateError(
        timeline.migrationDiagnostic ??
            'Legacy snapshot migration is not valid for this timeline.',
      );
    }
    await store.saveMigratedSnapshot(
      projectId: timeline.projectId,
      clips: timeline.clips,
      selectedClipIndex: timeline.selectedClipIndex,
      trimRange: timeline.trimRange,
      exports: timeline.exports,
    );
  }

  ProjectEditorTimeline _mapSnapshot({
    required m2.Project project,
    required List<m2.Clip> sources,
    required EditorProjectSnapshot snapshot,
    required EditorSnapshotSource source,
    String? legacyPath,
    InvalidEditorSnapshotException? canonicalError,
  }) {
    final byId = {for (final clip in sources) clip.id: clip};
    final byPath = <String, List<m2.Clip>>{};
    for (final clip in sources) {
      byPath.putIfAbsent(clip.localPath, () => []).add(clip);
    }
    final occurrences = <String, int>{};
    final unmatched = <UnmatchedTimelineItem>[];
    final mapped = <VideoClip>[];

    for (var index = 0; index < snapshot.clips.length; index++) {
      final saved = snapshot.clips[index];
      m2.Clip? sourceClip;
      if (saved.sourceClipId != null) {
        sourceClip = byId[saved.sourceClipId];
        if (sourceClip != null && sourceClip.localPath != saved.path) {
          sourceClip = null;
        }
      } else {
        final pathMatches = byPath[saved.path] ?? const <m2.Clip>[];
        if (pathMatches.length == 1) sourceClip = pathMatches.single;
      }

      if (sourceClip == null) {
        unmatched.add(UnmatchedTimelineItem(index: index, path: saved.path));
        mapped.add(saved);
        continue;
      }

      final occurrenceKey =
          '${sourceClip.id}:${saved.sourceStart.inMilliseconds}:'
          '${saved.duration.inMilliseconds}';
      final occurrence = occurrences.update(
        occurrenceKey,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      mapped.add(
        saved.copyWith(
          sourceClipId: sourceClip.id,
          timelineItemId:
              saved.timelineItemId ??
              _timelineId(
                project.id,
                sourceClip.id,
                saved.sourceStart.inMilliseconds,
                saved.duration.inMilliseconds,
                occurrence: occurrence,
              ),
        ),
      );
    }

    final exports = snapshot.exports
        .map(
          (entry) => SavedExport(
            filePath: entry.filePath,
            projectId: project.id,
            duration: entry.duration,
            quality: entry.quality,
            exportedAt: entry.exportedAt,
            thumbnailPath: entry.thumbnailPath,
          ),
        )
        .toList(growable: false);
    final itemIdCounts = <String, int>{};
    for (final clip in mapped) {
      final id = clip.timelineItemId;
      if (id != null) {
        itemIdCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final duplicateIds =
        itemIdCounts.entries
            .where((entry) => entry.value > 1)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    return ProjectEditorTimeline(
      projectId: project.id,
      clips: List.unmodifiable(mapped),
      selectedClipIndex: snapshot.clips.isEmpty
          ? 0
          : snapshot.selectedClipIndex.clamp(0, snapshot.clips.length - 1),
      trimRange: snapshot.trimRange,
      exports: List.unmodifiable(exports),
      source: source,
      unmatchedItems: List.unmodifiable(unmatched),
      duplicateTimelineItemIds: List.unmodifiable(duplicateIds),
      legacyPath: legacyPath,
      canonicalError: canonicalError,
    );
  }

  List<m2.Clip> _validateAndSort(m2.Project project, List<m2.Clip> clips) {
    final ids = <String>{};
    for (final clip in clips) {
      if (clip.projectId != project.id) {
        throw ArgumentError('Clip ${clip.id} belongs to another project.');
      }
      if (clip.id.isEmpty || !ids.add(clip.id)) {
        throw ArgumentError('Clip IDs must be non-empty and unique.');
      }
      if (clip.durationMs < 0) {
        throw ArgumentError('Clip duration cannot be negative.');
      }
    }
    return List.of(clips)..sort((a, b) => a.order.compareTo(b.order));
  }

  String _timelineId(
    String projectId,
    String clipId,
    int startMs,
    int durationMs, {
    int occurrence = 0,
  }) {
    final key =
        '$projectId\u0000$clipId\u0000$startMs\u0000$durationMs\u0000$occurrence';
    return 'm5:${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}';
  }

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;
}
