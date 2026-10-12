# PitchCut AI: Team Contracts

Everyone codes against this file. If you need to change something, open a PR
that edits this file first and tag the people affected.

## 1. Global rules
- All times are in **milliseconds (ms)**.
- All file paths are **absolute local paths** (strings).
- Scores are whole numbers from **0 to 100**.
- Dates are stored as ISO-8601 strings in code (Firestore Timestamp inside M2's repositories only).
- Platform for now: **Android**. Keep platform-specific code behind the interfaces below so iOS can be added later.
- Videos stay **on the device**. Firestore stores only project info, scores and captions.
  (Change this only if the team decides to use cloud storage.)

## 2. Data models (owner: M2, folder `lib/models/`)

### Project
| Field | Type | Notes |
|---|---|---|
| id | String | |
| userId | String | Firebase Auth uid |
| title | String | |
| createdAt | String | ISO-8601 |
| updatedAt | String | ISO-8601 |
| clipIds | List<String> | In playback order |
| exportedVideoPath | String? | Local path of the last export |
| latestReportId | String? | |

### Clip
| Field | Type | Notes |
|---|---|---|
| id | String | |
| projectId | String | |
| localPath | String | |
| durationMs | int | |
| width | int | pixels |
| height | int | pixels |
| sensorDataPath | String? | Accelerometer/gyroscope file from recording |
| order | int | Position in the project |

### Caption
| Field | Type | Notes |
|---|---|---|
| id | String | |
| startMs | int | |
| endMs | int | Must be greater than startMs |
| text | String | |

### PauseSegment
| Field | Type |
|---|---|
| startMs | int |
| endMs | int |

### PerformanceReport
| Field | Type | Notes |
|---|---|---|
| id | String | |
| projectId | String | |
| createdAt | String | ISO-8601 |
| score | int | 0-100, overall |
| pauses | List<PauseSegment> | Long pauses found |
| faceScore | int | 0-100 |
| stabilityScore | int | 0-100 |
| paceScore | int | 0-100, or -1 if no captions yet |
| tips | List<String> | Up to 3 short tips |

Every model has `toJson()`, `fromJson()` and `copyWith()`.

## 3. Repositories (owner: M2, folder `lib/data/`)

```dart
abstract class AuthRepository {
  Stream<String?> authStateChanges();          // uid or null
  Future<void> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

abstract class ProjectRepository {
  Future<Project> createProject(String title);
  Future<List<Project>> listProjects();
  Future<void> updateProject(Project project);
  Future<void> deleteProject(String projectId);
  Future<void> saveClip(Clip clip);
  Future<List<Clip>> listClips(String projectId);
  Future<void> deleteClip(String clipId);
}

abstract class ReportRepository {
  Future<void> saveReport(PerformanceReport report);
  Future<List<PerformanceReport>> listReports(String projectId);
}

abstract class CaptionRepository {
  Future<void> saveCaptions(String projectId, List<Caption> captions);
  Future<List<Caption>> loadCaptions(String projectId);
}
```

## 4. Editing engine (owner: M4 builds it, M5 and M7 call it)

Dart side lives in `lib/features/editor/engine/editor_engine.dart`.
Native side (Kotlin + Media3) lives in `android/.../media3/`.
MethodChannel name: **`pitchcut/editor`**. Event channel for export progress: **`pitchcut/editor/progress`**.

```dart
class ExportEvent {
  final double progress;       // 0.0 to 1.0
  final String? outputPath;    // set only on the final event
  const ExportEvent(this.progress, [this.outputPath]);
}

abstract class EditorEngine {
  /// Keeps the part between startMs and endMs. Returns the new file path.
  Future<String> trim({required String path, required int startMs, required int endMs});

  /// Splits one clip at atMs. Returns [firstPartPath, secondPartPath].
  Future<List<String>> cut({required String path, required int atMs});

  /// Joins clips end to end, in the order given.
  Future<String> merge({required List<String> paths});

  /// degrees is 90, 180 or 270 (clockwise).
  Future<String> rotate({required String path, required int degrees});

  /// Crop rectangle in pixels of the source video.
  Future<String> crop({
    required String path,
    required int left,
    required int top,
    required int width,
    required int height,
  });

  /// Renders the final video. Captions are burned in when the list is not empty.
  Stream<ExportEvent> export({
    required List<String> clipPaths,
    List<Caption> captions = const [],
    int? targetHeight,         // e.g. 720 or 1080
  });

  Future<void> cancelExport();

  /// One loudness value (0.0 silent to 1.0 loud) every 100 ms.
  Future<List<double>> getLoudnessSamples(String path);
}
```

**Error codes** (thrown as `PlatformException.code`):
`FILE_NOT_FOUND`, `INVALID_RANGE`, `UNSUPPORTED_FORMAT`, `EXPORT_FAILED`, `CANCELLED`.

**Until M4 finishes:** M5 develops against a `FakeEditorEngine` (returns the same
path after a short delay). It lives in `test/fakes/`.

## 5. Analysis (owner: M6, folder `lib/features/analysis/`)

```dart
abstract class AnalysisService {
  /// Finds pauses of at least minPauseMs (default 1500) using loudness samples.
  Future<List<PauseSegment>> detectPauses(String videoPath, {int minPauseMs = 1500});

  /// Runs everything and returns a full report (not yet saved).
  Future<PerformanceReport> analyse({required Clip clip, List<Caption> captions = const []});
}
```

Score weights (can be tuned after testing):
pauses 30%, face position 25%, stability 25%, speaking pace 20%.

## 6. Recording output (owner: M3, folder `features/capture/`)

- After recording or importing, M3 creates a `Clip` and saves it through `ProjectRepository`.
- Sensor data is saved next to the video as a JSON file named `<clipId>_sensors.json`:
  `[{ "tMs": 0, "ax": 0.0, "ay": 0.0, "az": 0.0, "gx": 0.0, "gy": 0.0, "gz": 0.0 }, ...]`

## 7. File locations
| What | Where |
|---|---|
| Recorded and imported videos | App documents folder `/videos/<projectId>/` |
| Edited and exported videos | App documents folder `/exports/<projectId>/` |
| Sensor files | Same folder as the clip |

## 8. Routes (owner: M1, file `lib/core/router/app_router.dart`)
| Route | Screen | Owner |
|---|---|---|
| /login | LoginScreen | M2 |
| /home | HomeScreen | M1 |
| /record | CaptureScreen | M3 |
| /history | HistoryScreen | M7 |
| /profile | ProfileScreen | M2 |
| /editor | EditorScreen | M5 |
| /analysis | AnalysisScreen | M6 |
| /captions | CaptionsScreen | M7 |

Pass data with `extra` or a path parameter (agree on `/editor?projectId=...` style
when the first real screen needs it, and update this file).

## 9. Who owns which folder
| Folder | Owner |
|---|---|
| core/, shared/, .github/, docs/ | M1 |
| models/, data/, features/auth/, features/profile/ | M2 |
| features/capture/ | M3 |
| android/.../media3/, features/editor/engine/ | M4 |
| features/editor/ (UI), features/export/ | M5 |
| features/analysis/ | M6 |
| features/captions/, features/history/ | M7 |

Need a change in someone else's folder? Message the owner or open an issue first.