import AppKit
import Carbon.HIToolbox

/// PoC text expander (Tinycast-style): listen-only CGEvent tap + keyword buffer.
///
/// Built-in: typing `$time` expands to `yyyy-MM-dd HH:mm` (e.g. `2026-10-21 13:50`).
/// Needs Accessibility (same grant as clipboard ⌘V / window snap).
enum TextExpanderSnippets {
    /// Trigger typed by the user (case-insensitive match).
    static let timeKeyword = "$time"

    /// `2026-10-21 13:50` — local datetime without seconds.
    static func formattedTime(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func expansion(forKeyword keyword: String, now: Date = Date()) -> String? {
        if keyword.lowercased() == timeKeyword {
            return formattedTime(now)
        }
        return nil
    }
}

/// Pure buffer matcher — Tinycast `SnippetKeywordPolicy` distilled to one keyword for PoC.
struct TextExpanderPolicy: Sendable {
    struct Match: Equatable, Sendable {
        let keyword: String
        let deletionCount: Int
        let expansion: String
    }

    enum Input: Equatable, Sendable {
        case text(String)
        case deleteBackward
        case reset
        case ignored
    }

    static let timeout: TimeInterval = 15
    static let maximumBufferLength = 64

    private(set) var buffer = ""
    private var lastInputAt: Date?

    private let keyword: String
    private let nowProvider: @Sendable () -> Date

    init(
        keyword: String = TextExpanderSnippets.timeKeyword,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keyword = keyword.lowercased()
        self.nowProvider = now
    }

    mutating func process(_ input: Input, at now: Date? = nil) -> Match? {
        let now = now ?? nowProvider()
        if case .ignored = input { return nil }
        if let lastInputAt, now.timeIntervalSince(lastInputAt) > Self.timeout {
            reset()
        }

        switch input {
        case .ignored:
            return nil
        case .reset:
            reset()
            return nil
        case .deleteBackward:
            lastInputAt = now
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        case .text(let text):
            lastInputAt = now
            buffer.append(text)
            if buffer.count > Self.maximumBufferLength {
                buffer.removeFirst(buffer.count - Self.maximumBufferLength)
            }
        }

        let normalized = buffer.lowercased()
        guard normalized.hasSuffix(keyword) else { return nil }
        let deletionCount = keyword.count
        guard let expansion = TextExpanderSnippets.expansion(forKeyword: keyword, now: now) else {
            reset()
            return nil
        }
        reset()
        return Match(keyword: keyword, deletionCount: deletionCount, expansion: expansion)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastInputAt = nil
    }

    static func classifyInput(
        text: String?,
        isSynthetic: Bool,
        secureEventInputEnabled: Bool,
        isFlagsChanged: Bool,
        isKeyDown: Bool,
        hasCommandOrControl: Bool,
        isResetKey: Bool,
        isDeleteBackward: Bool
    ) -> Input {
        if isSynthetic { return .ignored }
        if secureEventInputEnabled || hasCommandOrControl || isResetKey { return .reset }
        if isFlagsChanged { return .ignored }
        guard isKeyDown else { return .ignored }
        if isDeleteBackward { return .deleteBackward }
        guard let text else { return .reset }
        return .text(text)
    }
}

// MARK: - Event tap

private let textExpanderEventTag: Int64 = 0x524F4F58 // "ROOX"

private func textExpanderCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let expander = Unmanaged<TextExpander>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { expander.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        DispatchQueue.main.async {
            expander.clearBuffer()
        }
        return Unmanaged.passUnretained(event)
    }

    let eventUserData = event.getIntegerValueField(.eventSourceUserData)
    let secureEventInputEnabled = IsSecureEventInputEnabled()
    let typeRaw = type.rawValue
    let flagsRaw = event.flags.rawValue
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    var length = 0
    var characters = [UniChar](repeating: 0, count: 16)
    event.keyboardGetUnicodeString(
        maxStringLength: characters.count,
        actualStringLength: &length,
        unicodeString: &characters
    )
    let text = length > 0 ? String(utf16CodeUnits: characters, count: length) : nil

    DispatchQueue.main.async {
        expander.processEvent(
            typeRaw: typeRaw,
            keyCode: keyCode,
            flagsRaw: flagsRaw,
            text: text,
            eventUserData: eventUserData,
            secureEventInputEnabled: secureEventInputEnabled
        )
    }
    return Unmanaged.passUnretained(event)
}

/// Global `$time` → formatted datetime expander. One instance owned by `AppDelegate`.
@MainActor
final class TextExpander {
    private var policy = TextExpanderPolicy()
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var appObserver: NSObjectProtocol?
    private var isExpanding = false
    private var loggedTapFailure = false

    func start() {
        guard tapPort == nil else { return }
        _ = FocusRestorer.ensureTrusted(prompt: true)
        installAppSwitchObserver()
        installTapIfPossible()
        FocusRestorer.log(
            "textexpander: start (ax=\(FocusRestorer.isTrusted() ? 1 : 0), tap=\(tapPort != nil ? 1 : 0))"
        )
    }

    func stop() {
        tearDownTap()
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }
        policy.reset()
        FocusRestorer.log("textexpander: stop")
    }

    func clearBuffer() {
        policy.reset()
    }

    fileprivate func tapWasDisabled() {
        policy.reset()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
            FocusRestorer.log("textexpander: re-enabled tap after disable")
        } else {
            installTapIfPossible()
        }
    }

    fileprivate func processEvent(
        typeRaw: UInt32,
        keyCode: Int,
        flagsRaw: UInt64,
        text: String?,
        eventUserData: Int64,
        secureEventInputEnabled: Bool
    ) {
        guard !isExpanding else { return }
        let flags = CGEventFlags(rawValue: flagsRaw)
        let input = TextExpanderPolicy.classifyInput(
            text: text,
            isSynthetic: eventUserData == textExpanderEventTag,
            secureEventInputEnabled: secureEventInputEnabled,
            isFlagsChanged: typeRaw == CGEventType.flagsChanged.rawValue,
            isKeyDown: typeRaw == CGEventType.keyDown.rawValue,
            hasCommandOrControl: flags.contains(.maskCommand) || flags.contains(.maskControl),
            isResetKey: Self.resetKeyCodes.contains(keyCode),
            isDeleteBackward: keyCode == kVK_Delete
        )
        guard let match = policy.process(input) else { return }
        FocusRestorer.log(
            "textexpander: match keyword=\(match.keyword) → \(match.expansion)"
        )
        expand(match)
    }

    private func expand(_ match: TextExpanderPolicy.Match) {
        isExpanding = true
        // Triggering key already reached the app (listen-only). Delete then type.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            guard Self.deleteBackward(count: match.deletionCount) else {
                FocusRestorer.log("textexpander: delete failed")
                self.isExpanding = false
                return
            }
            // Brief settle so the target applies deletions before insert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self else { return }
                defer { self.isExpanding = false }
                guard Self.typeUnicode(match.expansion) else {
                    FocusRestorer.log("textexpander: type failed")
                    return
                }
                FocusRestorer.log("textexpander: expanded \(match.expansion)")
            }
        }
    }

    private func installAppSwitchObserver() {
        guard appObserver == nil else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearBuffer()
            }
        }
    }

    private func installTapIfPossible() {
        guard tapPort == nil else { return }
        guard FocusRestorer.isTrusted() else {
            FocusRestorer.log("textexpander: tap deferred — Accessibility not trusted")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: textExpanderCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            if !loggedTapFailure {
                FocusRestorer.log("textexpander: failed to create event tap")
                loggedTapFailure = true
            }
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            FocusRestorer.log("textexpander: failed to create run-loop source")
            return
        }

        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        loggedTapFailure = false
        FocusRestorer.log("textexpander: event tap active")
    }

    private func tearDownTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    // MARK: - Synthetic keys (tagged so the tap ignores them)

    private static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: textExpanderEventTag)
    }

    private static func deleteBackward(count: Int) -> Bool {
        guard count > 0 else { return true }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let code = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            else { return false }
            down.flags = []
            up.flags = []
            tag(down)
            tag(up)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func typeUnicode(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        for scalar in text.unicodeScalars {
            var chars = Array(String(scalar).utf16)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            down.flags = []
            up.flags = []
            tag(down)
            tag(up)
            down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    private static let resetKeyCodes: Set<Int> = [
        kVK_Return,
        kVK_ANSI_KeypadEnter,
        kVK_Escape,
        kVK_Tab,
        kVK_LeftArrow,
        kVK_RightArrow,
        kVK_UpArrow,
        kVK_DownArrow,
        kVK_Home,
        kVK_End,
        kVK_PageUp,
        kVK_PageDown,
        kVK_ForwardDelete,
    ]
}
