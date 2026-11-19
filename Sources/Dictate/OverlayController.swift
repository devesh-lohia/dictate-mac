import AppKit
import Combine
import SwiftUI

/// Owns the floating, click-through, always-on-top window that shows the live text.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    private let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>
    private var cancellables = Set<AnyCancellable>()
    private var visibilityToken = 0

    init() {
        hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 90),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver              // above full-screen apps such as a full-screen Terminal
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false         // an accessory app is never "active"; do not auto-hide
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false        // lets you scroll back through long text; never takes keyboard focus
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        // Grow / shrink the window as the text changes.
        model.$text.combineLatest(model.$status, model.$textHeight).receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitToContent(animated: true) } }
            .store(in: &cancellables)
    }

    // MARK: - Show / hide

    func show() {
        visibilityToken += 1
        model.text = ""
        model.textHeight = 0
        model.isWorking = false
        model.status = "Listening"
        fitToContent(animated: false)
        place()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                self.panel.alphaValue = 1          // never leave a half-faded window behind
            }
        }
    }

    func hide() {
        visibilityToken += 1
        let token = visibilityToken
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, token == self.visibilityToken else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Content

    func setText(_ text: String) {
        model.text = text
        if !panel.isVisible { panel.orderFrontRegardless(); panel.alphaValue = 1 }
    }

    func setWorking(_ status: String) {
        model.status = status
        model.isWorking = true
    }

    func setListening() {
        model.status = "Listening"
        model.isWorking = false
    }

    /// Briefly show a status such as "Cleared" or "Typed", then return to "Listening".
    func flash(_ status: String, clearText: Bool = true) {
        if clearText { model.text = "" }
        model.status = status
        model.isWorking = false
        let token = visibilityToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, token == self.visibilityToken, self.model.status == status else { return }
            self.setListening()
        }
    }

    // MARK: - Layout

    private func fitToContent(animated: Bool) {
        // header (18) + gap (8) + text area (22...132) + vertical padding (16 + 16)
        let textArea = min(max(model.textHeight, 22), OverlayView.maxTextHeight)
        let height = ceil(16 + 18 + 8 + textArea + 16)
        var frame = panel.frame
        frame.size = NSSize(width: 480, height: height)
        if let screen = currentScreen() { frame.origin.x = screen.visibleFrame.midX - 240 }
        if abs(frame.height - panel.frame.height) < 0.5 && abs(frame.minX - panel.frame.minX) < 0.5 { return }   // nothing to do
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Bottom-centre of the screen the mouse is on.
    private func place() {
        guard let screen = currentScreen() else { return }
        var frame = panel.frame
        frame.origin = NSPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.minY + 72)
        panel.setFrame(frame, display: true)
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}
