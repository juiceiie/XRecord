import AppKit
import Carbon.HIToolbox

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    static let defaultQuickSearch = KeyboardShortcut(
        keyCode: 7,
        carbonModifiers: UInt32(optionKey),
        keyLabel: "X"
    )

    static let legacyQuickSearchDefault = KeyboardShortcut(
        keyCode: 49,
        carbonModifiers: UInt32(optionKey),
        keyLabel: "Space"
    )

    var displayText: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        keyLabel = Self.keyLabel(for: event)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let relevantFlags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if relevantFlags.contains(.control) { result |= UInt32(controlKey) }
        if relevantFlags.contains(.option) { result |= UInt32(optionKey) }
        if relevantFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if relevantFlags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc",
            115: "Home", 116: "⇞", 117: "⌦", 119: "End", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let label = specialKeys[event.keyCode] {
            return label
        }

        let functionKeys: [UInt16: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let label = functionKeys[event.keyCode] {
            return label
        }

        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

private let quickSearchHotKeySignature: OSType = 0x58524344 // XRCD

private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == quickSearchHotKeySignature,
          hotKeyID.id == 1 else {
        return OSStatus(eventNotHandledErr)
    }

    let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        service.onHotKey?()
    }
    return noErr
}

final class GlobalHotKeyService: ObservableObject {
    static let shared = GlobalHotKeyService()

    @Published private(set) var shortcut: KeyboardShortcut
    @Published private(set) var isRegistered = false

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hasInstalledHandler = false

    private let keyCodeKey = "quickSearchHotKey.keyCode"
    private let modifiersKey = "quickSearchHotKey.modifiers"
    private let keyLabelKey = "quickSearchHotKey.keyLabel"

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: keyCodeKey) != nil,
           defaults.object(forKey: modifiersKey) != nil,
           let keyLabel = defaults.string(forKey: keyLabelKey) {
            let savedShortcut = KeyboardShortcut(
                keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
                carbonModifiers: UInt32(defaults.integer(forKey: modifiersKey)),
                keyLabel: keyLabel
            )
            if savedShortcut == .legacyQuickSearchDefault {
                shortcut = .defaultQuickSearch
                defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
                defaults.set(Int(shortcut.carbonModifiers), forKey: modifiersKey)
                defaults.set(shortcut.keyLabel, forKey: keyLabelKey)
            } else {
                shortcut = savedShortcut
            }
        } else {
            shortcut = .defaultQuickSearch
        }
    }

    deinit {
        unregisterShortcut()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func start() {
        installHandlerIfNeeded()
        if hotKeyRef == nil {
            _ = registerShortcut(shortcut)
        }
    }

    func suspend() {
        unregisterShortcut()
    }

    func resume() {
        if hotKeyRef == nil {
            _ = registerShortcut(shortcut)
        }
    }

    @discardableResult
    func updateShortcut(from event: NSEvent) -> Bool {
        let candidate = KeyboardShortcut(event: event)
        guard candidate.carbonModifiers != 0 else { return false }

        let previous = shortcut
        unregisterShortcut()

        guard registerShortcut(candidate) else {
            _ = registerShortcut(previous)
            return false
        }

        shortcut = candidate
        save(candidate)
        return true
    }

    func restoreDefault() -> Bool {
        let previous = shortcut
        unregisterShortcut()
        let defaultShortcut = KeyboardShortcut.defaultQuickSearch
        guard registerShortcut(defaultShortcut) else {
            _ = registerShortcut(previous)
            return false
        }
        shortcut = defaultShortcut
        save(defaultShortcut)
        return true
    }

    private func installHandlerIfNeeded() {
        guard !hasInstalledHandler else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        hasInstalledHandler = status == noErr
    }

    private func registerShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        installHandlerIfNeeded()
        guard hasInstalledHandler else { return false }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: quickSearchHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            isRegistered = false
            return false
        }

        hotKeyRef = reference
        isRegistered = true
        return true
    }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isRegistered = false
    }

    private func save(_ shortcut: KeyboardShortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: modifiersKey)
        defaults.set(shortcut.keyLabel, forKey: keyLabelKey)
    }
}
