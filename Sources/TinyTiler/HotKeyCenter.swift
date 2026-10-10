import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey. Unlike CGEventTap or NSEvent global
/// monitors, this needs no Input Monitoring or Accessibility permission.
@MainActor
final class HotKeyCenter {
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x5454_4C52 // 'TTLR'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Returns false when the combo is already taken by another app (eventHotKeyExistsErr).
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) -> Bool {
        let id = EventHotKeyID(signature: Self.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        actions[nextID] = action
        refs.append(ref)
        nextID += 1
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

private func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers application-target events on the main thread.
    MainActor.assumeIsolated { center.fire(id) }
    return noErr
}
