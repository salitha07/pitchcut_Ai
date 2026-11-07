import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/trim_range.dart';
import '../models/video_clip.dart';

class EditorProjectSnapshot {
  const EditorProjectSnapshot({
    required this.clips,
    required this.selectedClipIndex,
    required this.trimRange,
  });

  final List<VideoClip> clips;
  final int selectedClipIndex;
  final TrimRange trimRange;
}

class EditorProjectStore {
  Future<File> _fileFor(String projectId) async {
    final root = await getApplicationSupportDirectory();
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
  }) async {
    final file = await _fileFor(projectId);
    final temporary = File('${file.path}.tmp');
    final json = {
      'clips': clips.map((clip) => clip.toJson()).toList(growable: false),
      'selectedClipIndex': selectedClipIndex,
      'trimRange': {
        'startMs': trimRange.start.inMilliseconds,
        'endMs': trimRange.end.inMilliseconds,
      },
    };
    await temporary.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
