# PitchCut AI

An Android app (Flutter) that helps students and job seekers record, edit and improve
short presentation videos. It suggests cuts for long pauses, checks face position and
camera stability, adds captions, and gives a presentation score.

## Tech stack
Flutter, Riverpod, go_router, Firebase (Auth and Firestore), Android Media3, ML Kit,
device camera, microphone and motion sensors.

Platform: **Android first**. iOS will be added later.

## Setup (first time)
1. Install Flutter **3.47.0 (stable)** and Android Studio. Run `flutter doctor` and fix any red items
   (for Android licenses: `flutter doctor --android-licenses`).
2. Clone and run:
```bash
   git clone https://github.com/salitha07/pitchcut_Ai.git
   cd pitchcut_Ai
   git checkout develop
   flutter pub get
   flutter run
```
3. Start an **Android emulator** (or plug in a phone) before `flutter run`. Do not pick Chrome or Edge.
4. Success: the app opens on Home with four tabs (Home, Record, History, Profile).

Firebase config files are already in the repo, so you don't need to run `flutterfire configure`.

### Windows tips
- If your project is on a different drive from Flutter (for example D: and C:), builds can
  fail. We keep `kotlin.incremental=false` in `android/gradle.properties` to avoid this.
- If `flutter test` crashes on your machine but passes in CI, run `flutter clean` first.

## How we work (the relay)
We build in order: each member finishes their whole part, writes a handoff note, and then
the next member starts.

| Order | Member | Part | Folders |
|---|---|---|---|
| 1 | M1 | Setup, shell, shared widgets, contracts | core/, shared/, .github/, docs/ |
| 2 | M2 | Models, auth, data | models/, data/, features/auth/, features/profile/ |
| 3 | M3 | Recording, import, sensors | features/capture/ |
| 4 | M4 | Android editing engine (Media3) | android/.../media3/, features/editor/engine/ |
| 5 | M5 | Editor UI, preview, export | features/editor/, features/export/ |
| 6 | M6 | AI analysis and score | features/analysis/ |
| 7 | M7 | Captions, history, testing, demo | features/captions/, features/history/ |

Progress is tracked on the **PitchCut AI Relay** project board.
All agreements (data models, editing functions, routes) are in [`docs/contracts.md`](docs/contracts.md).

## Git rules
- Branches: `main` (release only), `develop` (team branch), `feature/m<number>-<task>` for your work.
- Never push directly to `main` or `develop`. Open a Pull Request into `develop`.
- Every PR needs 1 reviewer and a green CI check (`flutter analyze` and `flutter test`).
- Commit messages: `feat:`, `fix:`, `docs:`, `chore:`, `test:`.
- Pull from `develop` every morning. Keep PRs small.
- Start your part only after the previous member's handoff note is merged.

## Useful commands
```bash
flutter analyze      # must show no issues
flutter test         # must pass
flutter run          # run on the emulator or phone
```

## Shared widgets
Use the team's widgets from `lib/shared/widgets/widgets.dart` (buttons, cards, loading,
error and empty views, confirm dialog). In the app, open **Home, then Widget gallery** to see them.