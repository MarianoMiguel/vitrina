import AppKit
import Carbon
import Foundation

struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard !Self.modifierOnlyKeyCodes.contains(keyCode) else { return nil }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 || Self.unmodifiedFunctionKeyCodes.contains(keyCode) else {
            return nil
        }

        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Representation for NSMenuItem.keyEquivalent so shortcuts render with
    /// native right-aligned glyphs (⌃⌥W) like Settings and Quit do.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let key = Self.keyEquivalents[keyCode] else { return nil }

        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return (key, flags)
    }

    private static let keyEquivalents: [UInt32: String] = {
        func functionKey(_ value: Int) -> String {
            UnicodeScalar(value).map(String.init) ?? ""
        }

        var map: [UInt32: String] = [:]
        for (code, name) in keyNames {
            if name.count == 1 {
                map[code] = name.lowercased()
            }
        }
        map[UInt32(kVK_Space)] = " "
        map[UInt32(kVK_Return)] = "\r"
        map[UInt32(kVK_Tab)] = "\t"
        map[UInt32(kVK_Escape)] = "\u{001B}"
        map[UInt32(kVK_Delete)] = "\u{0008}"
        map[UInt32(kVK_ForwardDelete)] = functionKey(NSDeleteFunctionKey)
        map[UInt32(kVK_Home)] = functionKey(NSHomeFunctionKey)
        map[UInt32(kVK_End)] = functionKey(NSEndFunctionKey)
        map[UInt32(kVK_PageUp)] = functionKey(NSPageUpFunctionKey)
        map[UInt32(kVK_PageDown)] = functionKey(NSPageDownFunctionKey)
        map[UInt32(kVK_LeftArrow)] = functionKey(NSLeftArrowFunctionKey)
        map[UInt32(kVK_RightArrow)] = functionKey(NSRightArrowFunctionKey)
        map[UInt32(kVK_UpArrow)] = functionKey(NSUpArrowFunctionKey)
        map[UInt32(kVK_DownArrow)] = functionKey(NSDownArrowFunctionKey)
        let fKeys: [(Int, Int)] = [
            (kVK_F1, NSF1FunctionKey), (kVK_F2, NSF2FunctionKey), (kVK_F3, NSF3FunctionKey),
            (kVK_F4, NSF4FunctionKey), (kVK_F5, NSF5FunctionKey), (kVK_F6, NSF6FunctionKey),
            (kVK_F7, NSF7FunctionKey), (kVK_F8, NSF8FunctionKey), (kVK_F9, NSF9FunctionKey),
            (kVK_F10, NSF10FunctionKey), (kVK_F11, NSF11FunctionKey), (kVK_F12, NSF12FunctionKey),
            (kVK_F13, NSF13FunctionKey), (kVK_F14, NSF14FunctionKey), (kVK_F15, NSF15FunctionKey),
            (kVK_F16, NSF16FunctionKey), (kVK_F17, NSF17FunctionKey), (kVK_F18, NSF18FunctionKey),
            (kVK_F19, NSF19FunctionKey), (kVK_F20, NSF20FunctionKey)
        ]
        for (code, value) in fKeys {
            map[UInt32(code)] = functionKey(value)
        }
        return map
    }()

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command),
        UInt32(kVK_Shift),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Option),
        UInt32(kVK_Control),
        UInt32(kVK_RightCommand),
        UInt32(kVK_RightShift),
        UInt32(kVK_RightOption),
        UInt32(kVK_RightControl),
        UInt32(kVK_Function)
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let unmodifiedFunctionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F13),
        UInt32(kVK_F14),
        UInt32(kVK_F15),
        UInt32(kVK_F16),
        UInt32(kVK_F17),
        UInt32(kVK_F18),
        UInt32(kVK_F19),
        UInt32(kVK_F20)
    ]

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "Left Arrow",
        UInt32(kVK_RightArrow): "Right Arrow",
        UInt32(kVK_DownArrow): "Down Arrow",
        UInt32(kVK_UpArrow): "Up Arrow",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20"
    ]
}

enum HotKeyPreferences {
    static func shortcut(for action: HotKeyAction) -> HotKeyShortcut {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: defaultsKey(for: action)),
              let keyCode = dictionary["keyCode"] as? Int,
              let modifiers = dictionary["modifiers"] as? Int else {
            return action.defaultShortcut
        }

        return HotKeyShortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    static func setShortcut(_ shortcut: HotKeyShortcut, for action: HotKeyAction) {
        UserDefaults.standard.set(
            [
                "keyCode": Int(shortcut.keyCode),
                "modifiers": Int(shortcut.modifiers)
            ],
            forKey: defaultsKey(for: action)
        )
    }

    static func resetShortcut(for action: HotKeyAction) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: action))
    }

    static func resetAllShortcuts() {
        HotKeyAction.allCases.forEach(resetShortcut)
    }

    static func conflictingAction(for shortcut: HotKeyShortcut, excluding action: HotKeyAction) -> HotKeyAction? {
        HotKeyAction.allCases.first { candidate in
            candidate != action && self.shortcut(for: candidate) == shortcut
        }
    }

    private static func defaultsKey(for action: HotKeyAction) -> String {
        "hotkeys.\(action.storageKey)"
    }
}
