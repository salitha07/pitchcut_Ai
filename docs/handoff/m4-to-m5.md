# Member 4 Handoff to Member 5 — PitchCut AI

This handoff describes the current editor engine implementation. M4 worked directly from Section 4 of [`docs/contracts.md`](../contracts.md); `docs/handoff/m3-to-m4.md` is not present in the repository.

## Corrections to the previous handoff

These previous statements did not match the implementation:

| Previous claim | Current behavior | Code evidence |
|---|---|---|
| `FakeEditorEngine` returns synthetic paths by default. | Its default is `useSyntheticPaths: false`; path-returning methods pass through their input path where applicable. Synthetic paths are opt-in. | [`fake_editor_engine.dart`](../../test/fakes/fake_editor_engine.dart) |
| The debug screen is the app's initial route and is always registered. | The home page remains the initial route; `/engine-debug` is registered only when `kDebugMode` is true. | [`main.dart`](../../lib/main.dart) |
| Canceling only the Dart stream subscription does not cancel native export. | The wrapper's stream `onCancel` cancels its EventChannel subscription and invokes native `cancelExport`. | [`method_channel_editor_engine.dart`](../../lib/features/editor/engine/method_channel_editor_engine.dart) |
| Export always ends with a successful output-path event, and malformed/incomplete events produce `FormatException`. | A successful export emits the final event with `outputPath`, then closes. Errors terminate with a stream error and close. Malformed progress events are ignored; native stream completion closes the Dart stream without synthesizing `FormatException`. | [`method_channel_editor_engine.dart`](../../lib/features/editor/engine/method_channel_editor_engine.dart), [`ExportService.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/ExportService.kt) |
| Overlapping captions display only the earliest active caption. | All captions active at a frame are joined with newlines and drawn together. | [`CaptionBitmapOverlay.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/CaptionBitmapOverlay.kt) |
| Caption font size is 5% of frame height. | It is 4.5% of output-frame height, with a 12 px minimum. | [`ExportService.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/ExportService.kt), [`CaptionBitmapOverlay.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/CaptionBitmapOverlay.kt) |
| Rotate and crop can return `UNSUPPORTED_FORMAT`. | Their method allow-lists exclude that code; unsupported-format failures are returned as `EXPORT_FAILED`. | [`ErrorCodes.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/ErrorCodes.kt), [`EditorMethodHandler.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/EditorMethodHandler.kt) |
| Any loudness decoder failure is `UNSUPPORTED_FORMAT`. | Missing audio and unsupported output PCM format are `UNSUPPORTED_FORMAT`; other failures are mapped and may be `EXPORT_FAILED`. | [`LoudnessService.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/LoudnessService.kt), [`ErrorCodes.kt`](../../android/app/src/main/kotlin/com/pitchcut/pitchcut_ai/media3/ErrorCodes.kt) |

## What is available

- The Dart contract and platform-channel wrapper implement all eight Section 4 methods.
- Android registers `pitchcut/editor` and `pitchcut/editor/progress` and dispatches editing operations to Media3 services.
- Trim, cut, merge, rotate, crop, export, cancellation, caption burn-in, and audio loudness extraction have implementations.
- The temporary real-engine debug screen is available at `/engine-debug` in debug builds only. The app still starts at its home page.
- Native output files are written to the app cache directory. Copy an output elsewhere if it must persist beyond cache cleanup.

## Dart API

The following signatures are copied from [`editor_engine.dart`](../../lib/features/editor/engine/editor_engine.dart):

```dart
class ExportEvent {
  final double progress;
  final String? outputPath;

  const ExportEvent(this.progress, [this.outputPath]);
}

abstract class EditorEngine {
  Future<String> trim({
    required String path,
    required int startMs,
    required int endMs,
  });

  Future<List<String>> cut({
    required String path,
    required int atMs,
  });

  Future<String> merge({
    required List<String> paths,
  });

  Future<String> rotate({
    required String path,
    required int degrees,
  });

  Future<String> crop({
    required String path,
    required int left,
    required int top,
    required int width,
    required int height,
  });

  Stream<ExportEvent> export({
    required List<String> clipPaths,
    List<Caption> captions = const [],
    int? targetHeight,
  });

  Future<void> cancelExport();

  Future<List<double>> getLoudnessSamples(String path);
}
```

`ExportEvent.progress` is normalized to `0.0`–`1.0`. On successful export, `outputPath` is present on the terminal event.

## Platform-channel implementation

[`MethodChannelEditorEngine`](../../lib/features/editor/engine/method_channel_editor_engine.dart) uses:

- Method channel: `pitchcut/editor`
- Export event channel: `pitchcut/editor/progress`

The wrapper sends captions as maps containing `startMs`, `endMs`, and `text`; the Dart-only caption `id` is not sent. It checks returned paths, requires exactly two non-empty paths from `cut`, and parses numeric loudness entries as doubles. Unknown native error codes are normalized to `EXPORT_FAILED`; the five caller-visible contract codes are `FILE_NOT_FOUND`, `INVALID_RANGE`, `UNSUPPORTED_FORMAT`, `EXPORT_FAILED`, and `CANCELLED`.

### Export stream and cancellation

- Listen to the returned stream to receive progress and the terminal result.
- On success, the final event has `progress == 1.0` and the output path. The stream then closes.
- On failure or cancellation, the stream emits an error and closes; there is no success output-path event.
- Malformed progress events are ignored. If the native event stream ends without an output-path event, the Dart wrapper closes the stream; it does not create a `FormatException`.
- Only one native export runs at a time. Starting another while one is active fails with `EXPORT_FAILED`.
- `cancelExport()` completes normally when no export is active. During an active export, it requests native cancellation; the active export reports `CANCELLED` on its stream.
- Canceling the Dart export subscription invokes native cancellation through the wrapper's `onCancel`. A listener that has already canceled its subscription should not expect to receive the resulting stream error.

Example:

```dart
final EditorEngine engine = MethodChannelEditorEngine();

try {
  await for (final event in engine.export(
    clipPaths: [sourcePath],
    captions: const [],
    targetHeight: 1080,
  )) {
    debugPrint('Export ${(event.progress * 100).round()}%');
    if (event.outputPath != null) {
      debugPrint('Saved to ${event.outputPath}');
    }
  }
} on PlatformException catch (error) {
  if (error.code == 'CANCELLED') {
    debugPrint('Export cancelled');
  } else {
    debugPrint('Export failed [${error.code}]: ${error.message}');
  }
}
```

## Fake and real engine setup

`FakeEditorEngine` lives in [`test/fakes/fake_editor_engine.dart`](../../test/fakes/fake_editor_engine.dart), so it is for tests and UI development, not production imports.

```dart
final fake = FakeEditorEngine(
  delay: Duration.zero,
  useSyntheticPaths: false, // default
  methodErrors: {'trim': 'INVALID_RANGE'},
);
```

- Default delay is 50 ms and is configurable.
- By default, `trim`, `rotate`, and `crop` return their input path; `cut` returns two copies of a nonblank input path; `merge` returns its first path when present. An empty cut path, empty merge list, or empty export clip list uses a dummy fallback path. The fake does not validate media or mirror native validation.
- `useSyntheticPaths: true` opts into transformed-style dummy paths for path-returning operations, including export.
- Export emits progress values `0.0`, `0.25`, `0.50`, `0.75`, and `1.0`; its output path is set only on the final event. The fake returns 50 normalized dummy loudness samples.
- Set `methodErrors` or call `setMethodError` to simulate a method failure. `simulatedErrorCode` sets a global failure and `clearErrors()` resets configured failures.
- The fake records the latest method and arguments, including export captions and `targetHeight`.

Use the real Android engine in runtime code:

```dart
final EditorEngine engine = MethodChannelEditorEngine();
```

In tests, import the fake from the test tree and inject it into the widget under test:

```dart
import '../../../fakes/fake_editor_engine.dart';

final engine = FakeEditorEngine(delay: Duration.zero);
```

## Android behavior and errors

All errors crossing the engine boundary use one of the contract codes below. Incorrectly typed method arguments are reported as `INVALID_RANGE`; missing or blank required paths are `FILE_NOT_FOUND`.

| Method(s) | Possible error codes | Notes |
|---|---|---|
| `trim`, `cut`, `merge` | `FILE_NOT_FOUND`, `INVALID_RANGE`, `UNSUPPORTED_FORMAT`, `EXPORT_FAILED` | Invalid ranges/lists use `INVALID_RANGE`; missing files use `FILE_NOT_FOUND`. |
| `rotate` | `FILE_NOT_FOUND`, `INVALID_RANGE`, `EXPORT_FAILED` | Degrees must be 90, 180, or 270. `UNSUPPORTED_FORMAT` is excluded by the rotate allow-list and becomes `EXPORT_FAILED`. |
| `crop` | `FILE_NOT_FOUND`, `INVALID_RANGE`, `EXPORT_FAILED` | Crop rectangle must be valid and within source bounds. `UNSUPPORTED_FORMAT` is excluded by the crop allow-list and becomes `EXPORT_FAILED`. |
| `export` | `FILE_NOT_FOUND`, `INVALID_RANGE`, `UNSUPPORTED_FORMAT`, `EXPORT_FAILED`, `CANCELLED` | Empty clip lists, invalid target heights, and invalid caption timing use `INVALID_RANGE`. |
| `cancelExport` | No error when no export is active; active-export cancellation is `CANCELLED` on the export stream. | The method call itself completes normally for the no-active-export case. |
| `getLoudnessSamples` | `FILE_NOT_FOUND`, `UNSUPPORTED_FORMAT`, `EXPORT_FAILED` | No audio track and unsupported decoder PCM output are `UNSUPPORTED_FORMAT`. |

Media3 exception classification uses explicit error-code constants: file-not-found maps to `FILE_NOT_FOUND`; decoder/encoder initialization and unsupported decoder/encoder formats map to `UNSUPPORTED_FORMAT`; other and unknown Media3 failures map to `EXPORT_FAILED`. Per-method allow-lists then restrict which codes callers receive.

Rotation accepts 90, 180, or 270 degrees and passes that positive angle to Media3's `ScaleAndRotateTransformation`; the Dart API describes these as clockwise rotations.

## Caption burn-in

- Caption times are integer milliseconds on the concatenated export timeline. Earlier clip durations are added when evaluating later clips.
- A caption is active for `startMs <= frameTimeMs < endMs`; back-to-back captions meet at their shared boundary without an intended gap or overlap.
- Valid captions overlapping at a frame are joined with newlines and rendered together.
- The overlay is based on the output frame. It draws bold white text on a 50%-opaque black rounded rectangle, bottom-center with a margin of about 5% of frame height.
- Font size is 4.5% of output-frame height, with a 12 px minimum. Text wraps to at most three lines and the box is limited to 90% of frame width. Longer text is ellipsized; input beyond 8,192 Unicode code points is first shortened with an ellipsis.
- The overlay uses Android `TextPaint` and `StaticLayout`, rather than drawing characters individually.
- A captions argument that is not a list, or a list item that is not a map, is rejected with `INVALID_RANGE`. Within a map, missing or wrongly typed timing/text and blank text are skipped. A negative start or `endMs <= startMs` fails export with `INVALID_RANGE`.
- Captions whose start is at or beyond the total export duration are ignored. Captions beginning before the end of the video can remain active through the end of the output.
- An empty caption list adds no caption overlay.

## Loudness samples

`getLoudnessSamples(path)` decodes the first audio track and returns one value per 100 ms of **audio-track duration**, including a final partial window. Mono and multichannel decoded PCM are accumulated by frame across decoder buffers.

Only 16-bit PCM output is supported. The service requires the decoder output format to supply sample rate, channel count, and PCM encoding; other/missing encodings return `UNSUPPORTED_FORMAT`. RMS is divided by the fixed signed-16-bit full scale (`32768`) and clamped to `0.0`–`1.0`, so silence is `0.0` and normalization does not depend on the loudest value in the file. A file without an audio track returns `UNSUPPORTED_FORMAT`.

## Debug screen

[`EngineDebugScreen`](../../lib/features/editor/debug/engine_debug_screen.dart) uses the real `MethodChannelEditorEngine`, includes controls for the editing operations, export/cancel and loudness, and displays progress and a copyable action log. It is marked temporary. [`main.dart`](../../lib/main.dart) keeps the app's home page as its initial route and registers `/engine-debug` only when `kDebugMode` is true; the route is therefore unavailable in release builds.

## Known limitations

- Native editing channels are implemented for Android; this repository has no matching iOS `pitchcut/editor` handler.
- Inputs are local file paths. The Android services use filesystem paths rather than resolving remote URLs or arbitrary content URIs.
- Output files are stored in the app cache directory and are not automatically saved to the gallery or persistent application storage.
- Export accepts only target heights 720 and 1080; omitting `targetHeight` selects 1080 on Android.
- Only one native export may run at a time.
- Loudness extraction requires an audio track and 16-bit PCM decoder output.
- The fake returns dummy data and does not exercise real media processing.

## Verification status

The following are code-level and automated build/test verification results:
- `flutter analyze`: **PASSED** (0 issues found).
- `flutter test`: **PASSED** (all 52 tests passed across fake engine, method channel wrapper, caption serialization, export cancellation, error mapping, and debug screen widgets).
- `./gradlew :app:compileDebugKotlin`: **PASSED** (built with 0 errors).
- `./gradlew :app:testDebugUnitTest`: **PASSED** (all Media3 error code mapping, loudness accumulator windowing, and output cleanup tests passed).
- `flutter build apk --debug`: **PASSED** (generated `build/app/outputs/flutter-apk/app-debug.apk`).

Device verification has not been recorded here. Tick these only after running the checks on a device:

- [ ] Trim, cut, merge, rotate, and crop outputs verified on device.
- [ ] Export playback, output dimensions, audio, progress, and cancellation verified on device.
- [ ] Caption appearance, timing, overlap, and empty-caption export verified on device.
- [ ] Loudness mono/stereo, partial-window, silence, and no-audio cases verified on device.
- [ ] Debug screen operations verified against the native Android engine on device.
