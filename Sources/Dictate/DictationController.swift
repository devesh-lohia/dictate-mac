import AppKit
import DictateCore

/// The dictation state machine: start → live preview → voice commands → clean up → insert.
@MainActor
final class DictationController {
    let overlay = OverlayController()
    let transcriber = Transcriber()
    private let audio = AudioCapture()
    private let cleaner = Cleaner()
    private let inserter = TextInserter()

    private(set) var isListening = false { didSet { onListeningChanged?(isListening) } }
    var onListeningChanged: ((Bool) -> Void)?

    private var previewTimer: Timer?
    private var meterTimer: Timer?
    private var session = 0          // bumps on every start
    private var epoch = 0            // bumps every time the buffer is discarded (voice commands)
    private var previewInFlight = false

    /// "done" / "clear" only act after a quiet pause, so they are not triggered by the word inside a sentence.
    private static let doneWords = ["done"]
    private static let clearWords = ["clear"]
    private static let pauseSeconds: TimeInterval = 2.5
    private var pending: (kind: String, text: String, since: Date)?

    // MARK: - Start up

    func loadModels() async throws {
        try await transcriber.load(directory: Pref.modelDirectory)
        cleaner.prewarm()
    }

    // MARK: - Start / stop

    func toggle() { isListening ? stop() : start() }

    func start() {
        guard !isListening else { return }
        guard transcriber.isReady else {
            overlay.show()
            overlay.setWorking("Loading model")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if self?.isListening == false { self?.overlay.hide() }
            }
            return
        }
        do { try audio.start(minLevel: Pref.minLevelValue) }
        catch { Log.write("audio start failed: \(error)"); return }

        Log.write("start")
        session += 1; epoch += 1; pending = nil
        isListening = true
        playSound("Tink")
        overlay.show()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.overlay.model.level = self?.audio.level ?? 0 }
        }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPreview() }
        }
    }

    /// Stops listening. With `insert: false` (the "close listener" command) everything said is thrown away.
    func stop(insert: Bool = true) {
        guard isListening else { return }
        isListening = false
        previewTimer?.invalidate(); meterTimer?.invalidate()
        overlay.model.level = 0
        playSound("Pop")
        let mySession = session

        if !insert {
            audio.stop()
            audio.discard()
            overlay.flash("Closed", clearText: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, mySession == self.session, !self.isListening else { return }
                self.overlay.hide()
            }
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)       // let the last audio arrive
            audio.stop()
            let samples = audio.snapshot()
            Log.write("stop samples=\(samples.count) \(audio.statsDescription)")
            overlay.setWorking("Transcribing")

            var text = ""
            if let transcript = await transcriber.transcribe(samples) {
                switch SpeechFilter.evaluate(transcript) {
                case .accept(let t): text = t
                case .reject(let reason): Log.write("ignored (\(reason)): \(transcript.text)")
                }
            }
            if VoiceCommands.trailingMatch(in: text, phrases: Pref.clearPhraseList + Self.clearWords) != nil {
                text = ""                                                   // "scratch that" then stop = discard
            } else if let body = VoiceCommands.trailingMatch(in: text, phrases: Pref.typePhraseList + Self.doneWords) {
                text = body                                                 // "type that" / "done" then stop = insert
            } else if VoiceCommands.trailingMatch(in: text, phrases: Pref.stopPhraseList) != nil {
                text = ""                                                   // "close listener": discard everything
            }
            if Pref.cleanupEnabled, !text.isEmpty {
                overlay.setText(text)
                overlay.setWorking("Cleaning up")
                text = await cleaner.clean(text)
            }
            // Close the window only if the user has not started a new dictation in the meantime.
            if mySession == session && !isListening { overlay.hide() }
            guard !text.isEmpty else { return }
            Log.write("insert: \(text)")
            inserter.insert(text)
        }
    }

    // MARK: - Live preview and voice commands

    private func refreshPreview() {
        guard isListening, !previewInFlight else { return }
        previewInFlight = true
        let samples = audio.snapshot()
        let myEpoch = epoch, mySession = session
        Task {
            let transcript = await transcriber.transcribe(samples)
            previewInFlight = false
            guard isListening, mySession == session, myEpoch == epoch, let transcript, !transcript.text.isEmpty else { return }

            switch SpeechFilter.evaluate(transcript) {
            case .reject(let reason):
                Log.write("ignored (\(reason)): \(transcript.text)")
            case .accept(let text):
                handle(spoken: text)
            }
        }
    }

    private func handle(spoken text: String) {
        if VoiceCommands.trailingMatch(in: text, phrases: Pref.clearPhraseList) != nil {
            Log.write("command: scratch that")
            discardBuffer()
            overlay.flash("Cleared")
        } else if VoiceCommands.trailingMatch(in: text, phrases: Pref.stopPhraseList) != nil {
            Log.write("command: close listener (discarding)")
            stop(insert: false)                     // stop listening, type nothing
        } else if let body = VoiceCommands.trailingMatch(in: text, phrases: Pref.typePhraseList) {
            Log.write("command: type that -> \(body)")
            typeAndKeepListening(body)
        } else if let body = VoiceCommands.trailingMatch(in: text, phrases: Self.doneWords) {
            overlay.setText(text)
            if pauseElapsed(kind: "done", text: text) {
                Log.write("command: done (after pause) -> \(body)")
                typeAndKeepListening(body)
            }
        } else if VoiceCommands.trailingMatch(in: text, phrases: Self.clearWords) != nil {
            overlay.setText(text)
            if pauseElapsed(kind: "clear", text: text) {
                Log.write("command: clear (after pause)")
                discardBuffer()
                overlay.flash("Cleared")
            }
        } else {
            pending = nil
            overlay.setText(text)
        }
    }

    /// True once the same trailing command text has stayed unchanged for `pauseSeconds`.
    private func pauseElapsed(kind: String, text: String) -> Bool {
        if let p = pending, p.kind == kind, p.text == text {
            if Date().timeIntervalSince(p.since) >= Self.pauseSeconds { pending = nil; return true }
            return false
        }
        pending = (kind, text, Date())
        return false
    }

    /// Cleans and types `body`, empties the buffer, and leaves the live window open.
    private func typeAndKeepListening(_ body: String) {
        pending = nil
        discardBuffer()
        guard !body.isEmpty else { overlay.flash("Nothing to type"); return }
        overlay.setText(body)
        overlay.setWorking("Cleaning up")
        Task {
            let final = Pref.cleanupEnabled ? await cleaner.clean(body) : body
            inserter.insert(final + " ")
            overlay.flash("Typed")
            Log.write("typed: \(final)")
        }
    }

    private func discardBuffer() {
        epoch += 1
        audio.discard()
    }

    private func playSound(_ name: String) {
        guard Pref.soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
