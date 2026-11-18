import AppKit

/// Inserts text at the cursor of whatever app is focused, by pasting.
/// (Pasting works in every app; direct Accessibility insertion is silently ignored by many of them.)
/// The clipboard is marked transient so clipboard managers skip it, and your previous clipboard is restored.
final class TextInserter {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type] = d } }
            return dict
        }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)   // "v"
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Put the user's clipboard back, unless something else copied in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard pasteboard.changeCount == ourChange else { return }
            pasteboard.clearContents()
            guard !saved.isEmpty else { return }
            let items: [NSPasteboardItem] = saved.map { dict in
                let it = NSPasteboardItem()
                for (type, data) in dict { it.setData(data, forType: type) }
                return it
            }
            pasteboard.writeObjects(items)
        }
    }
}
