import Carbon
import Foundation
import os

/// Registers global hotkeys with Carbon, which does not need Accessibility access.
@MainActor
final class HotKeyCenter {
    typealias Handler = @MainActor () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: "com.mardinli.tapmix", category: "hotkeys")

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            tapmixHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            log.error("Could not install the hotkey handler: \(status)")
        }
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping Handler) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x5450_4D58), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("Could not register hotkey \(id): \(status)")
            return
        }
        hotKeyRefs.append(ref)
        handlers[id] = handler
        log.info("Registered hotkey \(id)")
    }

    fileprivate func dispatch(id: UInt32) {
        handlers[id]?()
    }
}

private func tapmixHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
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
    guard status == noErr else { return status }

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        center.dispatch(id: hotKeyID.id)
    }
    return noErr
}
