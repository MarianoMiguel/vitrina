import Carbon
import Foundation

enum HotKeyAction {
    case focusedWindow
    case focusedMonitor
    case clear
}

final class HotKeyController {
    private let handler: (HotKeyAction) -> Void
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    init(handler: @escaping (HotKeyAction) -> Void) {
        self.handler = handler
    }

    func register() throws {
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

        try registerHotKey(keyCode: UInt32(kVK_ANSI_W), id: 1, target: target)
        try registerHotKey(keyCode: UInt32(kVK_ANSI_M), id: 2, target: target)
        try registerHotKey(keyCode: UInt32(kVK_ANSI_C), id: 3, target: target)
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

    private func registerHotKey(keyCode: UInt32, id: UInt32, target: EventTargetRef?) throws {
        AppLogger.shared.log("registerHotKey id=\(id) keyCode=\(keyCode)")
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("DST1"), id: id)
        let modifiers = UInt32(controlKey | optionKey)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            target,
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )

        guard status == noErr else {
            throw DynamicShareTargetError.hotKeyRegistrationFailed("RegisterEventHotKey \(id) returned \(status)")
        }

        refs.append(hotKeyRef)
    }

    private func handle(id: UInt32) {
        NSLog("Dynamic Share Target hotkey pressed: \(id)")
        AppLogger.shared.log("hotkey pressed id=\(id)")

        switch id {
        case 1:
            handler(.focusedWindow)
        case 2:
            handler(.focusedMonitor)
        case 3:
            handler(.clear)
        default:
            break
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
