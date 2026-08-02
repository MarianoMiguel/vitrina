import Carbon
import Foundation

enum HotKeyAction: Int, CaseIterable, Hashable {
    case focusedWindow = 1
    case focusedMonitor = 2
    case clear = 3
    case followFocus = 4

    var title: String {
        switch self {
        case .focusedWindow: "Focused Window"
        case .focusedMonitor: "Focused Monitor"
        case .clear: "Clear"
        case .followFocus: "Follow Focus"
        }
    }

    var storageKey: String {
        switch self {
        case .focusedWindow: "focusedWindow"
        case .focusedMonitor: "focusedMonitor"
        case .clear: "clear"
        case .followFocus: "followFocus"
        }
    }

    var defaultShortcut: HotKeyShortcut {
        switch self {
        case .focusedWindow:
            HotKeyShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey))
        case .focusedMonitor:
            HotKeyShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        case .clear:
            HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
        case .followFocus:
            HotKeyShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey))
        }
    }

    var hotKeyID: UInt32 {
        UInt32(rawValue)
    }
}

final class HotKeyController {
    private let handler: (HotKeyAction) -> Void
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    init(handler: @escaping (HotKeyAction) -> Void) {
        self.handler = handler
    }

    func register() throws {
        unregister()
        AppLogger.shared.log("registering hotkeys")
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let target = GetApplicationEventTarget()

        let status = InstallEventHandler(
            target,
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else {
                    return result
                }

                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.handle(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        guard status == noErr else {
            throw DynamicShareTargetError.hotKeyRegistrationFailed("InstallEventHandler returned \(status)")
        }

        do {
            for action in HotKeyAction.allCases {
                try registerHotKey(
                    shortcut: HotKeyPreferences.shortcut(for: action),
                    action: action,
                    target: target
                )
            }
        } catch {
            unregister()
            throw error
        }
    }

    func unregister() {
        for ref in refs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        refs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerHotKey(shortcut: HotKeyShortcut, action: HotKeyAction, target: EventTargetRef?) throws {
        AppLogger.shared.log("registerHotKey action=\(action.storageKey) keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers)")
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("DST1"), id: action.hotKeyID)

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            target,
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )

        guard status == noErr else {
            throw DynamicShareTargetError.hotKeyRegistrationFailed("RegisterEventHotKey \(action.title) returned \(status)")
        }

        refs.append(hotKeyRef)
    }

    private func handle(id: UInt32) {
        NSLog("%@ hotkey pressed: %d", AppMetadata.productName, id)
        AppLogger.shared.log("hotkey pressed id=\(id)")

        guard let action = HotKeyAction(rawValue: Int(id)) else {
            return
        }

        handler(action)
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
