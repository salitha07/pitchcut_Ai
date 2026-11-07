import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/trim_range.dart';
import '../models/video_clip.dart';
import '../models/video_export_state.dart';

class SavedExport {
  const SavedExport({
    required this.filePath,
    required this.projectId,
    required this.duration,
    required this.quality,
    required this.exportedAt,
    this.thumbnailPath,
  });

  final String filePath;
  final String projectId;
  final Duration duration;
  final VideoExportQuality quality;
  final DateTime exportedAt;
  final String? thumbnailPath;

  Map<String, Object?> toJson() => {
    'filePath': filePath,
    'projectId': projectId,
    'durationMs': duration.inMilliseconds,
    'quality': quality.name,
    'exportedAt': exportedAt.toIso8601String(),
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
  };

  factory SavedExport.fromJson(Map<String, dynamic> json) => SavedExport(
    filePath: json['filePath'] as String,
    projectId: json['projectId'] as String,
    duration: Duration(milliseconds: json['durationMs'] as int),
    quality: VideoExportQuality.values.firstWhere(
      (value) => value.name == json['quality'],
    ),
    exportedAt: DateTime.parse(json['exportedAt'] as String),
    thumbnailPath: json['thumbnailPath'] as String?,
  );
}

class EditorProjectSnapshot {
  const EditorProjectSnapshot({
    required this.clips,
    required this.selectedClipIndex,
    required this.trimRange,
    this.exports = const [],
  });

  final List<VideoClip> clips;
  final int selectedClipIndex;
  final TrimRange trimRange;
  final List<SavedExport> exports;
}

class EditorProjectStore {
  EditorProjectStore({Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;

  Future<Directory> get _root async =>
      _rootDirectory ?? await getApplicationSupportDirectory();

  Future<File> _fileFor(String projectId) async {
    final root = await _root;
    final directory = Directory('${root.path}/editor_projects');
    await directory.create(recursive: true);
    final safeId = base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
    return File('${directory.path}/$safeId.json');
  }

  Future<EditorProjectSnapshot?> load(String projectId) async {
    final file = await _fileFor(projectId);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final clips = (json['clips'] as List<dynamic>)
          .map((clip) => VideoClip.fromJson(clip as Map<String, Object?>))
          .toList(growable: false);
      final range = json['trimRange'] as Map<String, dynamic>?;
      return EditorProjectSnapshot(
        clips: clips,
        selectedClipIndex: json['selectedClipIndex'] as int? ?? 0,
        trimRange: TrimRange(
          start: Duration(milliseconds: range?['startMs'] as int? ?? 0),
          end: Duration(milliseconds: range?['endMs'] as int? ?? 0),
        ),
        exports: (json['exports'] as List<dynamic>? ?? const [])
            .map((item) => SavedExport.fromJson(item as Map<String, dynamic>))
            .where((item) => item.projectId == projectId)
            .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String projectId,
    required List<VideoClip> clips,
    required int selectedClipIndex,
    required TrimRange trimRange,
    List<SavedExport>? exports,
  }) async {
    final file = await _fileFor(projectId);
    final savedExports =
        exports ?? (await load(projectId))?.exports ?? const [];
    final json = {
      'clips': clips.map((clip) => clip.toJson()).toList(growable: false),
      'selectedClipIndex': selectedClipIndex,
      'trimRange': {
        'startMs': trimRange.start.inMilliseconds,
        'endMs': trimRange.end.inMilliseconds,
      },
      'exports': savedExports
          .map((item) => item.toJson())
          .toList(growable: false),
    };
    await _writeJson(file, json);
  }

  /// Copies an already verified export into durable project storage, then
  /// commits its metadata. The source recording and export staging file remain
  /// untouched. If metadata commit fails, the copied media is removed.
  Future<SavedExport> saveExportedVideo({
    required String projectId,
    required String sourcePath,
    required Duration duration,
    required VideoExportQuality quality,
    required DateTime exportedAt,
    List<SavedExport> existingExports = const [],
    List<VideoClip> clips = const [],
    int selectedClipIndex = 0,
    TrimRange trimRange = const TrimRange(
      start: Duration.zero,
      end: Duration.zero,
    ),
    List<int>? thumbnailBytes,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() == 0) {
      throw FileSystemException(
        'Verified export file is missing or empty.',
        sourcePath,
      );
    }
    final root = await _root;
    final safeId = base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
    final directory = Directory('${root.path}/project_exports/$safeId');
    await directory.create(recursive: true);
    final stamp = exportedAt.microsecondsSinceEpoch;
    var suffix = 0;
    var destination = File('${directory.path}/edited_$stamp.mp4');
    while (await destination.exists()) {
      suffix++;
      destination = File('${directory.path}/edited_${stamp}_$suffix.mp4');
    }
    final thumbnail = thumbnailBytes == null
        ? null
        : File('${directory.path}/${destination.uri.pathSegments.last.replaceFirst('.mp4', '.jpg')}');
    var copied = false;
    try {
      await source.copy(destination.path);
      copied = true;
      if (await destination.length() != await source.length()) {
        throw FileSystemException('The saved video copy is incomplete.', destination.path);
      }
      if (thumbnail != null)
        await thumbnail.writeAsBytes(thumbnailBytes!, flush: true);
      final item = SavedExport(
        filePath: destination.path,
        projectId: projectId,
        duration: duration,
        quality: quality,
        exportedAt: exportedAt,
        thumbnailPath: thumbnail?.path,
      );
      final file = await _fileFor(projectId);
      EditorProjectSnapshot? prior = await load(projectId);
      final exports = [...(prior?.exports ?? existingExports), item];
      await _writeJson(file, {
        'clips': (prior?.clips ?? clips)
            .map((clip) => clip.toJson())
            .toList(growable: false),
        'selectedClipIndex': prior?.selectedClipIndex ?? selectedClipIndex,
        'trimRange': {
          'startMs': (prior?.trimRange ?? trimRange).start.inMilliseconds,
          'endMs': (prior?.trimRange ?? trimRange).end.inMilliseconds,
        },
        'exports': exports
            .map((entry) => entry.toJson())
            .toList(growable: false),
      });
      return item;
    } catch (_) {
      if (copied && await destination.exists()) await destination.delete();
      if (thumbnail != null && await thumbnail.exists())
        await thumbnail.delete();
      rethrow;
    }
  }

  Future<void> _writeJson(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    final hadOriginal = await file.exists();
    try {
      if (await backup.exists()) await backup.delete();
      if (hadOriginal) await file.rename(backup.path);
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await backup.exists()) await backup.rename(file.path);
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
