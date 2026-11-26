# Tempo

AI contributors: read [AGENTS.md](AGENTS.md) for architecture, verification, deployment, and operational context.

A native SwiftUI exercise timer for iPhone and iPad, supporting iOS 17 and later. Workouts require no account or network connection. The feature-request form uses an internet connection; the app has no third-party dependencies.

## Run

1. Open `Tempo.xcodeproj` in Xcode.
2. Select the **Tempo** scheme and an iPhone simulator, then press **Run**.
3. To run on your iPhone, select your device and choose your Apple development team under **Signing & Capabilities** for both the **Tempo** and **TempoActivity** targets.

The included **Everyday energy** routine is ready to try. Tap **Create routine** to build your own.

Simulator previews: [library](design/library.png), [routine](design/routine.png), [preparation](design/preparation.png), [landscape countdown](design/countdown.png), [rest](design/rest.png), [completion](design/complete.png), [editor](design/editor.png), and [icon picker](design/icon-picker.png).

Feature requests: [form](design/feature-request-form.png), [confirmation](design/feature-request-success.png), and [saved retry](design/feature-request-retry.png).

New screens: [workout history](design/workout-history.png), [workout settings](design/workout-settings.png), and [Lock Screen countdown and alert](design/lock-screen.png).

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
- Hear spoken exercise names and durations, countdowns, and completion. Turn spoken cues off in **Workout settings** for the original tones, or toggle voice during a workout.
- See workout history with date, actual workout time, skipped intervals, and finished/ended-early status. The weekly summary includes rest time and excludes preparation, pauses, and skipped time.
- Keep the workout running when you lock the screen or switch apps. A Live Activity shows the overall time left on the Lock Screen and Dynamic Island; tap it to return to Tempo.
- Restore an unfinished workout after relaunch. If it finished while Tempo was suspended, its history entry is saved once when you reopen the app.
- Mute sounds during a workout. Step changes and completion also provide haptics on supported hardware.
- Keep the screen awake while the timer runs.
- Send an idea from **Workout settings → Request a feature**, with a required reply email. Requests are private to the developer; email is used only to respond about the request.

**Feature requests:** The form accepts a 3–120-character title and 10–4,000-character description, counted as Unicode code points to match the API. A reply email is required, supports common ASCII addresses and plus addressing, and is limited to 254 characters. The form explains what is sent before submission. Email ownership is not verified, and collecting an address does not subscribe the user or send an automatic email.

Drafts are stored in the app's private Application Support folder, excluded from backup, and protected on iOS. Before sending, Tempo saves an immutable payload and a random request ID. A failed or uncertain request can be retried with that same ID, including after relaunch; fields stay locked until receipt is confirmed or the user explicitly discards the saved copy. Discarding a local copy does not retract an already received request. A confirmed receipt clears the saved draft. Networking uses an ephemeral session and does not follow redirects or log request contents. The endpoint is public and has no client secret.

**Lock Screen alerts:** Open **Workout settings → Enable interval alerts** before starting a workout. Tempo prepares short speech sound files, then asks iOS to deliver interval and completion notifications even while the app is suspended. With spoken cues off (or if a speech file cannot be generated), notifications use tones. Foreground countdowns use the device’s media volume; locked-screen notifications follow silent mode, Focus, and notification sound settings. Muting a workout also silences its scheduled alerts.

The Live Activity displays the **overall workout countdown**, including preparation, rather than a potentially stale current interval. Pause and skip controls are in the app. At zero, reopen Tempo to finalize the completion display and save history. Live Activities require permission in iOS Settings and can stay active for up to eight hours. Workouts still keep time when Live Activities or notifications are disabled.

For routines with more than 63 upcoming intervals, the system notification limit means Tempo schedules the next 63 interval alerts plus completion. Reopening Tempo refreshes the schedule. Notifications may be delayed or suppressed by iOS settings; they are not precision alarms. No silent background audio, server, or background execution entitlement is used to keep the app awake. The timer reconciles continuous-clock deadlines when execution resumes; a saved checkpoint allows recovery after process termination. Foreground audio interruptions pause the workout when delivered to the active app.

Routines are saved atomically in the app’s Application Support directory. Deleting all routines leaves an empty library; the starter routine is added only on first launch. If an existing save cannot be read, the app preserves it and reports the problem instead of replacing it.

## Verification

Core tests cover preparation, deadline accuracy, countdown cue timing, pause/resume, skipping, background/relaunch reconciliation, notification schedules and limits, actual workout time, history deduplication and persistence, corrupt-file preservation, weekly totals, persistence of 150 routines, and compatibility with routines saved before icons were added:

```sh
swift test --disable-swift-testing
```

UI tests exercise creation, persistence across relaunch, editing/deletion, natural completion, pause/resume, skipping, muting, restart, background continuation, history recovery/deletion, spoken-cue preferences, notification permission, and the Live Activity. They use separate routine and history files.

```sh
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

`testVisualTour` saves screenshots of the main screens as Xcode test attachments.

Feature-request tests cover required email, validation, payload encoding, receipt matching, duplicate prevention, persistence across relaunch, and storage failures. `FeatureRequestUITests` exercises the form and captures empty, filled, retry, and success screens. UI tests use an isolated draft file and a debug-only fake sender, so automated UI checks do not upload requests. The API is tested separately against its live endpoint.

Verified: 44 core tests; targeted simulator checks for background continuation, completion after force-quit, history persistence/deletion, spoken-cue preferences, early-ended workouts, notification permission, Live Activity rendering, pause/skip/restart, and orientation. Simulator and unsigned iOS device builds pass.

Physical-device notification audio, Focus behavior, and haptics require device verification; simulator checks cannot establish their behavior on a locked physical iPhone.

## Project layout

- `Tempo/Core`: models, JSON persistence, and a deterministic timer state machine.
- `Tempo/UI`: SwiftUI library, editor, routine detail, and workout screens.
- `Tempo/Timer`: main-thread workout orchestration and interruption handling.
- `Tempo/Audio`: bundled PCM playback, foreground speech, and generated notification speech sounds.
- `TempoActivity` and `Shared`: Lock Screen / Dynamic Island Live Activity extension and shared attributes.
- `Tests/TempoCoreTests`: portable core tests.
- `TempoUITests`: simulator interaction tests.

`python3 scripts/generate_project.py` regenerates the Xcode project, app icon, and WAV cues using only Python’s standard library. Run it after adding new Swift source files. The generated project and resources are already included.

## Feature-request backend

The [backend](backend/README.md) implements a public `POST /v1/feature-requests` API on AWS. App users submit requests with a reply email; reviewing stored requests requires your AWS identity or an authorized owner login in the optional [web dashboard](backend/DASHBOARD.md). It includes AWS CDK infrastructure, validation and permission tests, deployment instructions, and a live smoke test. The iOS submission form is available under Workout settings → Help shape Tempo → Request a feature.
