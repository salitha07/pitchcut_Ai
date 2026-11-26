
# PitchCut AI — M3 to M4 Handoff

## 1. Handoff Information

- Project: PitchCut AI
- Platform: Flutter / Firebase
- Development priority: Android first, iOS later
- Source member: M3 — Video Capture and Sensor Logging
- Receiving member: M4
- Source branch: feature/vedio-recorder
- Status: M3 implementation and initial Android testing completed
- Handoff acceptance: Pending M4 review

## 2. Implemented Features

Member 3 implemented the following functionality:

- Camera preview using the Flutter camera package
- Front and rear camera switching
- Video recording with start and stop controls
- Recording duration timer
- Optional 0, 3, 5 and 10-second countdown
- Face framing overlay
- Video import from the device gallery
- Recorded and imported video playback
- Android camera lifecycle handling
- Attempted video recovery after recording interruption
- Accelerometer and gyroscope sensor logging
- Sensor sample validation and JSON serialization
- Local video and sensor file storage
- Firebase project and clip metadata saving
- Error handling for incomplete local file writes
- Preservation of local files when Firebase saving fails

## 3. Main Files

### Capture UI

`lib/features/capture/capture_screen.dart`

Responsibilities:

- Initialize and release camera resources
- Start and stop video recordings
- Import video from the gallery
- Show countdown and framing overlay
- Preview recorded or imported videos
- Handle Android lifecycle transitions
- Trigger project saving

### Framing Guide

`lib/features/capture/widgets/framing_guide.dart`

Responsibility:

- Display the camera framing overlay

### Video Storage

`lib/features/capture/services/video_storage_service.dart`

Responsibilities:

- Copy video into application documents storage
- Validate saved video existence and nonzero size
- Handle incomplete video copy failures
- Detect common storage-full errors
- Clean up files before Firestore writes begin

### Sensor Logging

`lib/features/capture/services/sensor_logging_service.dart`

Responsibilities:

- Subscribe to accelerometer and gyroscope streams
- Collect timestamped samples
- Reject invalid sensor values
- Stop sensor subscriptions
- Validate and serialize samples
- Save JSON beside the local video

### Project Saving

`lib/features/capture/services/capture_project_service.dart`

Responsibilities:

- Validate the authenticated Firebase user
- Generate project and clip identifiers
- Save the video locally
- Save available motion sensor data
- Create Project and Clip metadata
- Call the shared ProjectRepository

### Shared Models and Repository

- `lib/models/project.dart`
- `lib/models/clip.dart`
- `lib/data/project_repository.dart`

These files provide the shared data contract.
Coordinate any changes with their owner.

## 4. Video Storage Contract

Recorded and imported videos are stored inside the
application documents directory.

Expected layout:

```text
<app_documents>/
  videos/
    <projectId>/
      <clipId>.<video_extension>
      <clipId>_sensors.json
```

Important:

- Each project and clip has a generated UUID.
- Clip.localPath stores the local video path.
- Clip.sensorDataPath stores the local JSON path,
  or null when no sensor file is available.
- The current save flow does not upload video bytes
  to Firebase Storage.
- Local absolute paths are valid only within the
  application installation/device environment.
- Do not assume a local path can be opened
  directly on another device.

## 5. Sensor JSON Format

Sensor samples are stored as a JSON array.

Example:

```json
[
  {
    "tMs": 100,
    "ax": 0.1,
    "ay": 9.8,
    "az": 0.3,
    "gx": 0.01,
    "gy": 0.02,
    "gz": 0.03
  }
]
```

Field descriptions:

- tMs: elapsed time in milliseconds
- ax, ay, az: accelerometer readings
- gx, gy, gz: gyroscope readings

Validation rules:

- Each sample must contain all seven fields.
- tMs must be a nonnegative integer.
- Sensor values must be finite numbers.
- Sample timestamps must strictly increase.
- Missing sensor readings must not be fabricated.
- Sampling targets approximately 100 ms intervals.
- Actual intervals depend on device and OS behavior.

Imported gallery videos do not receive fabricated
motion sensor data.

Sensor availability is device-dependent.

## 6. Project and Clip Contract

The capture flow creates one new Project containing
one initial Clip.

Project fields used by the capture flow:

- id
- userId
- title
- createdAt
- updatedAt
- clipIds

Clip fields used by the capture flow:

- id
- projectId
- localPath
- durationMs
- width
- height
- sensorDataPath
- order

The initial clip has order = 0.

Additional fields may be supported by the shared
Project and Clip models.

## 7. Firestore Metadata Structure

Expected Firestore structure:

```text
users/
  <userId>/
    projects/
      <projectId>/
        clips/
          <clipId>/
```

The project document contains project metadata.

The clip document contains clip metadata, including
the local media path and optional sensor JSON path.

The current save implementation uses
ProjectRepository.createProject() followed by
ProjectRepository.addClip().

## 8. Integration Guidance for M4

1. Obtain the latest integrated project branch.
2. Review the Project and Clip models.
3. Query project and clip metadata through
   ProjectRepository.
4. Read Clip.localPath to locate locally stored video.
5. Check Clip.sensorDataPath before reading sensor JSON.
6. Decode and validate sensor JSON before processing.
7. Handle missing files and unsupported sensors.
8. Do not assume the media is stored remotely.
9. Test integration using a real Android device.
10. Coordinate model or repository changes with
    the appropriate team member.

## 9. Testing Evidence

Reported M3 verification:

- flutter analyze: No issues found
- flutter test: 56 automated tests passed
- Android APK: Built and launched successfully
- Android device used: PBFM00, Android 8.1
- Camera preview: Tested
- Video recording: Tested
- Video playback: Tested
- Gallery video import: Tested
- Recording interruption recovery: Tested
- Normal project saving: Tested
- Camera stability retest: Passed

The automated tests cover sensor validation
and simulated sensor event collection.

These results do not establish that every device,
storage failure or network failure scenario
has been tested.

## 10. Known Limitations

### Android-first implementation

Permanent local saving is currently designed for
Android. Browser recording and preview work, but
the browser prototype does not perform permanent
project saving through this implementation.

### Local-only video storage

Firebase stores metadata, not video bytes.

An absolute path stored in Firestore is not a
cross-device media URL.

### Interrupted recording

The application attempts to finalize recordings
when Android lifecycle changes interrupt capture.

Recovery cannot be guaranteed after force-stop,
process termination or device shutdown.

### Firebase partial-write risk

The existing repository calls createProject()
and addClip() separately.

An interrupted or uncertain Firestore operation
may leave incomplete metadata.

Local files are preserved after such failures
to avoid accidental media loss.

Automatic retry and full transactional recovery
are not yet implemented.

### Storage failure testing

Storage-full error handling has been implemented,
but an actual low-storage condition has not been
confirmed through a controlled Android test.

### Sensor support

Some devices may not expose both required sensors.

If either sensor is unavailable, the application
must not invent motion readings.

### File lifecycle

Project deletion and long-term cleanup of local
video and sensor files should be reviewed before
production use.

## 11. M4 Acceptance Checklist

- [ ] Review the capture module and relevant services
- [ ] Confirm shared model compatibility
- [ ] Confirm repository compatibility
- [ ] Open a saved local video on Android
- [ ] Read and validate a saved sensor JSON file
- [ ] Handle clips without sensor data
- [ ] Verify integration with M4 functionality
- [ ] Run flutter analyze
- [ ] Run flutter test
- [ ] Perform relevant Android integration tests
- [ ] Record any integration issues
- [ ] Confirm acceptance of the handoff

## 12. Final Handoff Status

M3 capture module implementation:
Completed for the agreed Android-first scope.

M3 initial testing:
Completed, subject to the limitations documented above.

M4 integration:
Pending.

M4 handoff acceptance:
Pending.

Do not mark the handoff as fully accepted until
M4 has reviewed and tested the integration.
