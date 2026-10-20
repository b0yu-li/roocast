import AppKit
import Combine
import Foundation

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date

    /// Single-line preview suitable for list rows.
    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 120 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]) + "…"
    }
}

/// Polls `NSPasteboard` for text changes and keeps a bounded in-memory history.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let maxItems: Int
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    /// Skip the next change when we write the pasteboard ourselves (paste path).
    private var ignoreNextChange = false

    init(maxItems: Int = 50, pollInterval: TimeInterval = 0.4) {
        self.maxItems = max(1, maxItems)
        self.pollInterval = pollInterval
    }

    func startMonitoring() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        // Capture initial clipboard so the first ⌘Esc isn't empty.
        ingestCurrentPasteboardIfNeeded()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        FocusRestorer.log("clipboard: monitoring started (interval=\(pollInterval)s, max=\(maxItems))")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Writes text to the general pasteboard without recording a duplicate history entry.
    func copyToPasteboard(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
        FocusRestorer.log("clipboard: wrote \(text.count) chars to pasteboard (changeCount=\(lastChangeCount))")
    }

    /// Case-insensitive substring filter; empty query returns full history (newest first).
    func items(matching query: String) -> [ClipboardItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return items }
        return items.filter { $0.text.lowercased().contains(lowered) }
    }

    /// Test / PoC helper — insert without touching the system pasteboard.
    func prependForTesting(_ text: String) {
        let item = ClipboardItem(id: UUID(), text: text, createdAt: Date())
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ignoreNextChange {
            ignoreNextChange = false
            FocusRestorer.log("clipboard: skipped self-write changeCount=\(count)")
            return
        }

        ingestCurrentPasteboardIfNeeded()
    }

    private func ingestCurrentPasteboardIfNeeded() {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        // Deduplicate consecutive identical copies.
        if items.first?.text == text {
            return
        }

        let item = ClipboardItem(id: UUID(), text: text, createdAt: Date())
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        FocusRestorer.log("clipboard: captured item len=\(text.count) history=\(items.count)")
    }
}

/// Posts ⌘V after focus has returned to the previous app.
enum ClipboardPaster {
    static func pasteCommandV(after delay: TimeInterval = 0.08) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                FocusRestorer.log("clipboard: paste failed — no CGEventSource")
                return
            }
            let keyV: CGKeyCode = 9
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
            else {
                FocusRestorer.log("clipboard: paste failed — could not create key events")
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            FocusRestorer.log("clipboard: posted ⌘V (frontmost=\(front))")
        }
    }
}
