# Contributing

Thanks for helping improve Dictate.

## Setup

1. Install Xcode (the macOS 26 SDK) and clone the repo.
2. `./scripts/setup-signing.sh` once, so macOS remembers the app's permissions across rebuilds.
3. `./build.sh` to build and install, then grant the permissions listed in the README.
4. `swift test` to run the unit tests.

`CLAUDE.md` has an architecture tour, debugging tricks (simulating speech without a microphone), and the pitfalls we have already hit. Please read it before changing the overlay, audio capture or voice commands.

## Making changes

- Keep logic that doesn't need UI or hardware in `Sources/DictateCore` and cover it with tests in `Tests/DictateCoreTests`.
- Match the existing style: small files, one responsibility each, comments that explain *why*.
- Add new settings in `Preferences.swift` (key, default, accessor) and surface them in `SettingsView.swift`.
- If you change the UI, run `./scripts/screenshots.sh` and commit the updated images in `docs/`.
- Keep the app on-device: no network calls other than the one-time model download, no analytics.

## Before opening a pull request

- `swift test` passes.
- `./build.sh --no-install` succeeds.
- You tested the change with the real app (press Fn, speak, check the text lands where expected).
- No personal paths, names or machine details in code, docs or screenshots.

## Ideas that would be welcome

- Windowed or streaming transcription for very long dictations
- Additional languages (the model supports 25 European languages; the filters currently default to English)
- Optional voice-lock (only transcribe an enrolled voice)
- Notarized release builds
