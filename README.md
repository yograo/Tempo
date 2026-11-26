# Tempo

A native SwiftUI exercise timer for iPhone and iPad, supporting iOS 17 and later. No account, network connection, or third-party dependencies required.

## Run

1. Open `Tempo.xcodeproj` in Xcode.
2. Select the **Tempo** scheme and an iPhone simulator, then press **Run**.
3. To run on your iPhone, select your device and choose your Apple development team under **Signing & Capabilities**.

The included **Everyday energy** routine is ready to try. Tap **Create routine** to build your own.

Simulator previews: [library](design/library.png), [routine](design/routine.png), [preparation](design/preparation.png), [landscape countdown](design/countdown.png), [rest](design/rest.png), [completion](design/complete.png), [editor](design/editor.png), and [icon picker](design/icon-picker.png).

## Features

- Save any number of routines locally; no app-imposed routine limit.
- Add named exercises and rest intervals, each lasting 1 second to 59 minutes, 59 seconds.
- Choose from 12 activity icons for each routine and exercise, including yoga, running, cycling, core, and strength training.
- Edit durations with minute/second wheels or quick presets.
- New exercises and rests reuse the last saved duration of the same type within the routine. Reopening a routine uses its last exercise and rest durations as defaults; canceling a step leaves defaults unchanged.
- Edit, duplicate, and delete routines; edit, reorder, and delete their steps.
- See each routine’s total time, exercise count, rest time, and ordered lineup.
- Run a large countdown with progress, next-step preview, pause/resume, skip, and restart.
- Get six seconds to prepare before the first exercise, with a beep each second. Restarting also includes preparation; the first exercise keeps its full duration.
- Workouts automatically switch to a panoramic landscape layout with an oversized timer and controls beside it. Exiting returns to portrait.
- Hear short cues in the final three seconds, a distinct tone when a step starts, and a 1.35-second tone at completion.
- Mute sounds during a workout. Step changes and completion also provide haptics on supported hardware.
- Keep the screen awake while the timer runs.

**Workout behavior:** Keep Tempo in the foreground while training. Switching apps, locking the phone, or an interruption pauses the timer; returning shows a Resume button. This version does not run or play alerts in the background. Audio uses the device’s media volume and mixes with other audio; turn up media volume to hear cues.

Routines are saved atomically in the app’s Application Support directory. Deleting all routines leaves an empty library; the starter routine is added only on first launch. If an existing save cannot be read, the app preserves it and reports the problem instead of replacing it.

## Verification

Core tests cover preparation, deadline accuracy, countdown cue timing, rest transitions, fractional pause/resume, skipping, completion, invalid input, persistence of 150 routines, and compatibility with routines saved before icons were added:

```sh
swift test --disable-swift-testing
```

UI tests exercise creation, persistence across relaunch, editing/deletion, natural completion, pause/resume, skipping, muting, restart, and interruption handling. They use a separate test data file.

```sh
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

`testVisualTour` saves screenshots of the main screens as Xcode test attachments.

Verified on the iPhone 17 Pro simulator (iOS 26.4): 23 core tests passed, along with targeted UI checks for icon persistence, six-second preparation, landscape orientation and portrait restoration, remembered durations, and natural completion. Physical-device audio and haptics have not been verified.

## Project layout

- `Tempo/Core`: models, JSON persistence, and a deterministic timer state machine.
- `Tempo/UI`: SwiftUI library, editor, routine detail, and workout screens.
- `Tempo/Timer`: main-thread workout orchestration and interruption handling.
- `Tempo/Audio`: bundled PCM audio playback.
- `Tests/TempoCoreTests`: portable core tests.
- `TempoUITests`: simulator interaction tests.

`python3 scripts/generate_project.py` regenerates the Xcode project, app icon, and WAV cues using only Python’s standard library. Run it after adding new Swift source files. The generated project and resources are already included.

## Feature-request backend

The [backend](backend/README.md) implements a public `POST /v1/feature-requests` API on AWS. App users submit requests with a reply email; reviewing stored requests requires your AWS identity. It includes AWS CDK infrastructure, validation and permission tests, deployment instructions, and a live smoke test. The iOS submission form is implemented in the `feature/feature-request-form` branch.
