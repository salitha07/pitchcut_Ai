# M5 to M6 handoff: Video Editor and Suggestion Bar

## 1. Overview

M5 adds a Flutter/Dart video editing flow around a selected local video file. The
main editor owns the clip sequence, preview player, playhead, trim selection,
command history, and project persistence. Flutter widgets render the timeline,
crop overlay, and suggestion UI. Native Android and iOS code handles video
thumbnails, trimming, and export processing.

The module is implemented in the repository. Android native code has compiled
and a real emulator export was verified and saved with project metadata. Full
device coverage of each editing operation and reopening a saved project after
app restart remain incomplete. See
[Testing results and limitations](#12-testing-results-and-known-limitations)
and `docs/handoff/m5-acceptance-review.md` before treating the module as
accepted.

## 2. Feature status

| Feature | Implementation status | Verification status |
|---|---|---|
| Open a local video in the editor | Implemented through the existing video picker and `VideoEditorScreen` | Not verified with a real recording in this environment |
| Preview play, pause, seek | Implemented with `video_player`; editor seeks across clip boundaries | Timeline seek interaction is tested; native playback is not |
| Multi-clip timeline, thumbnails, playhead | Implemented; timeline receives generated frame bytes and editor playback position | Playhead and supplied-thumbnail rendering are widget tested; native thumbnail extraction is not |
| Trim | Trim handles, validation, native trim operation, and history state are implemented | Range boundaries are tested; native trimmed output is not |
| Split, delete, reorder | Implemented with timeline operations and editor history | Operation logic is unit tested |
| Merge | Adjacent compatible clips merge logically when source ranges are contiguous; separate media is rendered into a merged file | Merge operation logic is tested; native rendering is not |
| Rotate and crop | Preview state and crop-frame interaction are implemented; export sends these transforms to native code | Rotation/crop logic and crop-frame gestures are tested; rendered media is not |
| Undo and redo | Snapshot command history integrated with editor actions | Multi-step history is unit tested |
| Export | Quality selection, real platform progress bridge, cancel path, output verification, and error UI are implemented | Controller state is tested with a fake backend; native export is not device-verified |
| Save export to project | Verified output is copied into app support storage and metadata is persisted | Copy, metadata, association, reload, and rollback are tested with test files; playable media is not verified by those storage tests |
| Suggestion Bar | Reusable component and editor callbacks are implemented; no M6 detection code exists | Empty state, details, timestamps, Accept, and Dismiss are widget tested |

“Implemented” describes code present in this repository; it is not a claim that
native media processing has passed device validation.

## 3. Architecture and important files

This is a Flutter app using Dart. The home screen uses `file_picker` to select a
video and pushes `VideoEditorScreen` with the selected file path. Navigation is
currently ordinary `MaterialPageRoute` navigation; there is no router package.

| File | Responsibility |
|---|---|
| `lib/main.dart` | App shell and local video picker/navigation entry point |
| `lib/features/editor/video_editor_screen.dart` | Editor orchestration: preview, selection, playhead, operations, history, persistence, export navigation, and supplied suggestions |
| `lib/features/editor/widgets/video_timeline.dart` | Horizontal clips, thumbnails, ruler, playhead, trim handles, selection, and reorder gestures |
| `lib/features/editor/widgets/crop_frame_editor.dart` | Interactive normalized crop frame |
| `lib/features/editor/widgets/suggestion_bar.dart` | Standalone suggestion presentation and Accept/Dismiss delegation |
| `lib/features/editor/models/video_clip.dart` | Immutable clip/source range and transform data |
| `lib/features/editor/models/trim_range.dart` | Clip-relative trim range validation and clamping |
| `lib/features/editor/models/crop_rect.dart` | Normalized crop bounds and move/resize operations |
| `lib/features/editor/models/editor_suggestion.dart` | Typed suggestion and supported action data |
| `lib/features/editor/models/editor_state_snapshot.dart` | State captured for undo/redo |
| `lib/features/editor/models/video_export_state.dart` | Export qualities and status state |
| `lib/features/editor/services/timeline_operations.dart` | Pure split/delete/reorder/merge/rotate/crop rules |
| `lib/features/editor/services/editor_command_history.dart` | Undo/redo snapshots |
| `lib/features/editor/services/editor_project_store.dart` | JSON project snapshots and exported-video metadata/file persistence |
| `lib/features/editor/services/video_trim_service.dart` | Thumbnail, single-clip trim, and legacy merge platform calls |
| `lib/features/editor/services/video_export_controller.dart` | Export lifecycle, progress, cancellation, and verification coordination |
| `lib/features/editor/services/video_export_service.dart` | Method/EventChannel export bridge and playable-file verification |
| `lib/features/editor/video_export_screen.dart` | Export settings/progress/error screens, saved-video player, and success screen |
| `android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/MainActivity.kt` | Android Media3 thumbnail/trim/export implementation |
| `ios/Runner/AppDelegate.swift` | iOS AVFoundation thumbnail/trim/export implementation |

## 4. Video editor component structure

`VideoEditorScreen(videoPath: ..., videoName: ...)` is the public editor entry
point. It probes the source using `VideoPlayerController.file`, creates an
initial `VideoClip`, and tries to restore the project snapshot keyed by the
source path. The editor maintains the ordered clip list and selected clip; the
timeline is a view that reports gestures back to the editor.

The editor’s app bar opens Export. Playback controls seek over the sum of clip
durations and activate the appropriate source clip. The lower editor area
contains edit controls, `VideoTimeline`, and saved exports when present. The
crop tool overlays `CropFrameEditor` on the preview and has Apply/Cancel
controls. `SuggestionBar` is displayed in the editor and receives suggestion
data through editor constructor properties; it does not call an M6 service.

The editor’s public M6 suggestion properties are:

```dart
final List<EditorSuggestion> suggestions;
final ValueChanged<EditorSuggestion>? onSuggestionAccepted;
final ValueChanged<EditorSuggestion>? onSuggestionDismissed;
```

The `suggestions` list defaults to empty. Dismissed or accepted IDs are hidden
for the lifetime of that editor State. M6 should provide stable, unique IDs and
use a new ID for a newly generated proposal.

## 5. Timeline and clip data models

`VideoClip` is an immutable timeline segment referencing a source file:

```dart
const VideoClip(
  path: '/local/path/recording.mp4',
  name: 'recording.mp4',
  duration: Duration(seconds: 8),
  sourceStart: Duration(seconds: 3),
  sourceDuration: Duration(seconds: 20),
  rotationDegrees: 0,
  crop: CropRect.full,
)
```

`duration` is the segment’s timeline duration. `sourceStart` locates the segment
inside the source; `sourceEnd` is `sourceStart + duration`. `sourceDuration`
describes the original source duration, not the clip’s selected range. A clip
may carry an in-memory `Uint8List` thumbnail; thumbnail bytes are not serialized
into the editor project JSON and can be regenerated from media.

The ordered `List<VideoClip>` defines timeline order and duration. The playhead
position supplied to `VideoTimeline` is a timeline-relative `Duration` from the
beginning of that ordered list. `TrimRange` values used by clip trim controls
are relative to the selected clip’s duration. `CropRect` coordinates are
normalized (`0.0` to `1.0`) against the source frame and enforces a minimum
normalized dimension of `0.05`.

## 6. Editing operation interfaces

Pure timeline operations live in `TimelineOperations`:

```dart
TimelineOperations.canSplit(clip, clipLocalPosition);
TimelineOperations.split(clips, clipIndex, clipLocalPosition);
TimelineOperations.delete(clips, clipIndex);
TimelineOperations.reorder(clips, fromIndex, toIndex);
TimelineOperations.canMerge(first, second);
TimelineOperations.canMergeWithoutRendering(first, second);
TimelineOperations.merge(clips, firstIndex, renderedClip: optionalRenderedClip);
TimelineOperations.rotate(clip);
TimelineOperations.crop(clip, cropRect);
```

Split requires both resulting parts to be at least 500 ms. Delete can return an
empty list. Merge only accepts adjacent clips with matching rotation/crop. If
they reference contiguous ranges of the same source, merge is a logical clip
operation; otherwise the editor first asks native processing to render the
adjacent media. Undo/redo records `EditorStateSnapshot` values containing
clips, selected clip index, trim range, and timeline position.

Trimming is media-backed: the editor calls `VideoTrimService.trim` with source
path and absolute source start/end, probes the result, and replaces the
selected timeline segment with the produced file. Rotation and crop are stored
as clip transform properties and sent to native export; their final rendered
result still requires device verification.

## 7. Video export workflow

The editor pushes `VideoExportScreen` with the ordered clip list, total edited
duration, source aspect ratio, project ID, and editor snapshot context. Export
quality is `VideoExportQuality.p480`, `.p720`, or `.p1080`. The controller passes
the full clip sequence and quality to `VideoExportService`.

Native bridge contract:

- `MethodChannel('pitchcut_ai/video_trim')`
- `EventChannel('pitchcut_ai/video_export_progress')`
- `startExportTimeline`: ordered clip maps include `inputPath`, `startMs`,
  `endMs`, `rotationDegrees`, optional normalized `crop`, plus `qualityHeight`,
  output path, and export ID.
- `cancelExport`: sends the active export ID.
- Progress events are maps containing `type: 'progress'`, the matching
  `exportId`, and a numeric normalized `progress` from `0.0` to `1.0`. A `ready`
  event is used when the event stream starts.

Android uses Media3 Transformer 1.11.1 with H.264 video and AAC audio. iOS uses
AVFoundation export sessions and chooses a compatible resolution preset. The
controller only reaches success after `VideoExportService.verifyOutput` checks
that the output exists, has nonzero size, initializes with `video_player`, and
reports positive duration and dimensions. Failed/cancelled staging output is
removed on a best-effort basis.

The estimated file size displayed in the UI is an estimate, not a guarantee.
Hardware encoder support and source characteristics affect the result.

## 8. Project storage integration

`EditorProjectStore` uses `getApplicationSupportDirectory()` by default. Project
JSON is stored under `editor_projects/` with the project ID encoded as base64url
for a filename. In current navigation, the project ID is the original video
path (`VideoEditorScreen.videoPath`), not a separately allocated project UUID.

The project snapshot contains the ordered clip list, selected clip index, trim
range, and `exports` metadata. Exported videos are copied under
`project_exports/<encoded-project-id>/`; original media is not replaced. Each
`SavedExport` stores `filePath`, `projectId`, `duration`, `quality`, `exportedAt`,
and optional `thumbnailPath`. Project JSON writes use a temporary file and
backup/rename path; export persistence removes the copied media if the metadata
commit fails. The editor reloads exports when returning from the export flow
and displays them as playable entries. The app home screen lists persisted
project IDs through `EditorProjectStore.listProjectIds()` and opens a selected
project in the editor. If a source path has expired (for example, a temporary
picker path removed after restart), the editor cannot initialize that source;
durable import of original media remains a recovery requirement.

Storage tests use temporary files and a new `EditorProjectStore` instance to
verify data reload. This simulates a fresh store, not an app process restart or
actual video decode. Because the project ID is a path, M6 should preserve the
same original path through navigation and should raise a migration design if
projects need stable IDs across moved/imported source files.

## 9. Suggestion Bar interface

`SuggestionBar` is a presentation component:

```dart
SuggestionBar(
  suggestions: suggestions,
  onAccept: (suggestion) {},
  onDismiss: (suggestion) {},
)
```

An empty list renders “No suggestions available.” Each item displays title,
optional details, and optional timeline markers. Accept and Dismiss each call
the matching callback with the original `EditorSuggestion`.

The data/action interface is defined in
`lib/features/editor/models/editor_suggestion.dart`:

```dart
const EditorSuggestion({
  required String id,
  required String title,
  String? details,
  Duration? startTime,
  Duration? endTime,
  EditorSuggestionAction? action,
})
```

Supported actions are currently `SeekSuggestionAction(Duration position)`,
`SplitSuggestionAction(Duration position)`, and
`TrimSuggestionAction(clipIndex: ..., range: ...)`. Positions for seek/split
are timeline-relative. A trim action’s range is relative to the referenced
clip segment. No action means that acceptance is callback-only.

## 10. Instructions for M6 to supply suggestions

Create suggestion objects in the M6 layer and pass them when constructing the
editor. Example:

```dart
import 'package:pitchcut_ai/features/editor/models/editor_suggestion.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';

final suggestions = <EditorSuggestion>[
  EditorSuggestion(
    id: 'pause-12-16-v1',
    title: 'Cut this pause?',
    details: 'This section may be a long pause.',
    startTime: const Duration(seconds: 12),
    endTime: const Duration(seconds: 16),
    action: const SplitSuggestionAction(Duration(seconds: 12)),
  ),
  EditorSuggestion(
    id: 'tighten-clip-0-v1',
    title: 'Shorten this clip?',
    details: 'Use the proposed in/out points.',
    startTime: const Duration(seconds: 2),
    endTime: const Duration(seconds: 7),
    action: const TrimSuggestionAction(
      clipIndex: 0,
      range: TrimRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 7),
      ),
    ),
  ),
];

VideoEditorScreen(
  videoPath: projectVideoPath,
  suggestions: suggestions,
  onSuggestionAccepted: (suggestion) {
    // Record user acceptance or update M6's suggestion state.
  },
  onSuggestionDismissed: (suggestion) {
    // Record dismissal or request replacement suggestions from M6.
  },
)
```

Suggestion generation, ranking, persistence, and refresh remain M6-owned. The
editor hides accepted/dismissed IDs for its current State; M6 should not reuse an
ID for a different proposal. The callbacks report the user's choice. They do
not return an action execution result.

## 11. How M6 can request an editing action

Attach one of the supported typed actions to an `EditorSuggestion`. On Accept,
the editor validates the data against its current timeline, then performs seek,
split, or trim through existing editor methods. Invalid/stale actions show an
editor message and do not mutate the timeline. The accepted callback still
reports that the user accepted the suggestion; it is not proof that the action
ran successfully.

The public interface does not currently expose suggestion actions for delete,
reorder, merge, rotate, or crop. Do not call the editor State’s private methods
or mutate editor internals from M6. If M6 needs another action, add a typed
action class and a validated dispatcher branch in the editor, then add unit or
widget coverage for that action.

## 12. Testing results and known limitations

Most recent full unit/widget test run: `flutter test --no-pub --reporter expanded`
completed with **34 tests passed and 0 failed**. `flutter analyze --no-pub`
completed with **No issues found**. Android `:app:compileDebugKotlin` and a
debug APK build succeeded after correcting the Media3 `Effects` import. On the
Android 17 emulator, an actual recorded video preview was opened and native
export produced a non-empty MP4 and project metadata (720p, duration 7,252 ms).
The exported file passed the app's player-based verification. See
`docs/handoff/m5-acceptance-review.md` for precise evidence and limitations.

Automated coverage includes:

- Timeline split/delete/reorder/merge/rotate/crop rules and trim boundaries.
- Crop-frame drag/resize behavior, timeline seeking/playhead movement, and
  supplied thumbnail rendering.
- Undo/redo sequences and redo invalidation.
- Export screen quality selection and export controller progress-state,
  cancellation, exporter errors, and output verifier gating using a fake backend.
- Project export copy, metadata, association, store reload, missing-file
  handling, and rollback on metadata failure.
- Suggestion Bar empty state, details, timestamps, Accept, and Dismiss callbacks.

Not verified end-to-end:

- Opening/playing/pause/seeking actual recorded files.
- Native thumbnail extraction, trim output, rendered merge, rotate/crop output.
- Real native export progress, native cancellation, and output playback on both
  platforms.
- Reopening and playing a saved output after an app process restart.
- The wiring of M6 callbacks against a live suggestion-generation service.

`integration_test/m5_editor_export_test.dart` provides a real-file Android
workflow for playback controls, export quality, native export, project metadata
and saved-output playback. It requires `M5_VIDEO_PATH` to identify a video
inside the app sandbox. The first integration-runner invocation stalled while
fetching AGP 8.11.0 artifacts from Google Maven and never reached the app; it is
not a passing test. Real native trim/merge/rotate/crop output, cancellation,
explicit failure UI, and process-restart recovery remain unverified. iOS native
compilation requires macOS/Xcode and was not run.

## 13. Setup and dependencies

Requirements:

- Flutter SDK with Dart SDK constraint `^3.13.0` from `pubspec.yaml`.
- `flutter pub get` to resolve Dart packages.
- Android Studio/Android SDK, Java 17, and the configured Gradle 9.3.1 wrapper
  distribution for Android builds.
- macOS with Xcode for iOS builds and device/simulator validation.

Relevant dependencies already in the project:

- `file_picker: ^13.3.2` — choose a local source video.
- `video_player: ^2.14.1` — preview and output verification/playback.
- `path_provider: ^2.1.6` — application support/documents directories.
- Flutter SDK `flutter_test` and `flutter_lints: ^6.0.0` for tests/lint rules.
- Android native `androidx.media3:media3-transformer:1.11.1` and
  `androidx.media3:media3-effect:1.11.1`.
- iOS uses system AVFoundation through `ios/Runner/AppDelegate.swift`.

Useful commands:

```sh
flutter pub get
flutter test --no-pub
flutter analyze --no-pub
```

Run Android/iOS builds and device tests only after their SDK/toolchain setup is
available. The platform channel names and payloads in
[Video export workflow](#7-video-export-workflow) must stay aligned between
Dart, Kotlin, and Swift.

## 14. Remaining work and integration risks

1. Run `integration_test/m5_editor_export_test.dart` when Google Maven is
   reachable and provide an app-local video fixture.
2. Verify actual source-file access after app restart. Current project identity
   and clip references use local paths, which can become stale if a source is
   moved or a picker-provided file is temporary.
3. Verify trim/merge/export codec compatibility and transform output on a range
   of device encoders and source aspect ratios.
4. M6 should validate suggestions against the current clip order/durations and
   refresh stale suggestions after edits. The current callback only indicates
   user acceptance/dismissal, not successful action execution.
5. If M6 needs more than seek/split/trim actions, expand the typed action model
   and editor dispatcher with validation and tests. Keep suggestion generation
   outside M5’s UI component.
6. Ensure project export storage retention/cleanup policy is defined; saved
   outputs are kept in app support storage and there is currently no export
   deletion UI.
