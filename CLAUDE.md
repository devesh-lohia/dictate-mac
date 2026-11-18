# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository. Humans: see README.md and CONTRIBUTING.md.

## What this is

**Dictate**: a macOS menu-bar app. Press Fn, speak, text is typed at the cursor. Swift package, no Xcode project. On-device Parakeet Ultra speech recognition (Core ML via FluidAudio), Apple Foundation Models for grammar cleanup, SwiftUI overlay with Liquid Glass.

## Commands

```sh
swift test                      # unit tests for DictateCore (fast)
./build.sh                      # build, sign, install to /Applications (kills the running app)
./build.sh --no-install         # build only -> build/Dictate.app
./build.sh --zip                # also build/Dictate-<version>.zip for a release
./scripts/setup-signing.sh      # one-time local code-signing identity ("DictateLocal")
./scripts/screenshots.sh        # regenerate docs/*.png from the installed app
```

The `Dictate` target needs the macOS 26 SDK (Liquid Glass, FoundationModels). Both are guarded with `#available`, so the built app runs on macOS 14+.

## Layout

```
Sources/DictateCore/     pure logic, no UI/audio: VoiceCommands, VoiceGate, TextRules   (unit-tested)
Sources/Dictate/         the app
  main.swift             entry; debug flags (--test, --demo, --settings=<tab>)
  AppDelegate.swift      menu bar item, settings window, wiring, SIGUSR1 debug toggle
  DictationController.swift   state machine: start -> live preview -> voice commands -> cleanup -> insert
  AudioCapture.swift     AVAudioEngine -> 16 kHz mono -> VoiceGate
  Transcriber.swift      Parakeet Ultra via FluidAudio (downloads the model on first run)
  SpeechFilter.swift     rejects other languages / low confidence
  Cleaner.swift          Apple on-device LM cleanup + rule-based fallback
  TextInserter.swift     paste at cursor, transient pasteboard, clipboard restore
  FnKeyMonitor.swift     CGEventTap on the Fn flag
  OverlayController.swift / OverlayView.swift   floating glass window + SwiftUI content
  SettingsView.swift, Preferences.swift, Permissions.swift, Log.swift, Debug.swift
Tests/DictateCoreTests/  XCTest
scripts/                 signing, icon generator, screenshot helpers
docs/                    README images (generated)
```

## Conventions

- Put anything testable (no UI, no hardware) in `DictateCore` and add a test.
- Settings are `UserDefaults` keys defined in `Preferences.swift`; SwiftUI binds with `@AppStorage` using the same keys. Add a default in `Pref.registerDefaults()`.
- Voice commands only trigger when the phrase is the **last** thing said (`VoiceCommands.trailingMatch`). That is deliberate: it avoids firing on phrases used inside sentences.
- The speech model is never committed. `Pref.defaultModelDir` is `~/.dictate/models/parakeet-ultra`; if missing, `Transcriber` downloads it.
- FluidAudio is pinned to an exact revision in `Package.swift`. Bump it deliberately and re-test.

## Gotchas (learned the hard way)

- **Permissions and signing.** Microphone, Accessibility and Input Monitoring are tied to the app's code signature. Ad-hoc signing changes it on every build, so macOS re-asks. `build.sh` signs with the `DictateLocal` identity if present (`scripts/setup-signing.sh` creates it). After the *first* grant of Input Monitoring/Accessibility the app must be relaunched.
- **Overlay sizing.** The window height is computed from `OverlayModel.textHeight` (reported by the SwiftUI view), not `fittingSize`, which reads stale layout. Only call `animator().setFrame` when the size really changes: repeated animations cancel the fade-in and leave the window at alpha 0.
- **Overlay must never take focus.** It is a non-activating `NSPanel`; it accepts mouse events only so you can scroll long text.
- **Live preview cost.** The whole buffer is re-transcribed once a second. That is fine (tens of ms) but would need windowing for very long sessions.
- **The cleanup LM can answer instead of edit.** `Cleaner` wraps text in `<transcript>` tags, uses a strict instruction plus an example, and `TextRules.isFaithfulRewrite` rejects outputs whose length drifts. Keep those guards.
- **Microphone right after launch.** Starting capture within a second or two of launch can return silent audio; real use (Fn long after launch) is unaffected.

## Debugging without a microphone or the Fn key

- `kill -USR1 $(pgrep -x Dictate)` toggles dictation. Combine with `say "..."` to simulate speech through the speakers.
- `Dictate.app/Contents/MacOS/Dictate --test file.wav` runs a file through the speech model, filters and cleanup. `DICTATE_GAIN=0.05` simulates a distant voice; `DICTATE_GATE=1` applies the volume gate.
- `open -n /Applications/Dictate.app --args --demo` shows the overlay with sample text; `--settings=general|voice|filters|permissions` opens Settings.
- **Launch debug windows with `open -n`, not by running the binary from a terminal.** From a terminal, macOS attributes microphone access to the terminal app and shows a prompt.
- Logs: `~/.dictate/log.txt`, and Console.app (subsystem `local.dictate`).

## Privacy rules for contributions

- Never commit personal paths, names, emails or machine details. Show paths with `~` (`abbreviatingWithTildeInPath`).
- Screenshots must capture only the app's own windows (`scripts/screenshots.sh` does this by window ID), never a full screen.
- Don't log or persist what the user says beyond the local debug log, and never send audio or text off the machine.
