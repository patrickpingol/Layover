import Carbon.HIToolbox

/// Registers the global "New Shelf" hot key. Carbon hot keys work in the sandbox and need no permission.
@MainActor
public final class HotKeyCenter {
    nonisolated private static let hotKeyID = EventHotKeyID(signature: OSType(0x4F44_7270), id: 1) // 'ODrp'

    private let onNewShelf: () -> Void
    // Only touched on the main actor, and in deinit once nothing else can reach the center.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?

    public init(onNewShelf: @escaping () -> Void) {
        self.onNewShelf = onNewShelf
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Makes `combo` the hot key, replacing any earlier one. Nil leaves no hot key.
    /// Returns false when `combo` couldn't be registered, for example because another app holds it;
    /// there is then no hot key.
    @discardableResult
    public func register(_ combo: KeyCombo?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let combo else { return true }
        guard installHandlerIfNeeded() else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, Self.hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr else { return false }
        hotKeyRef = ref
        return true
    }

    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        return status == noErr
    }

    nonisolated fileprivate static func isNewShelfHotKey(_ event: EventRef?) -> Bool {
        var pressed = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
        )
        return status == noErr && pressed.signature == hotKeyID.signature && pressed.id == hotKeyID.id
    }

    fileprivate func hotKeyPressed() {
        onNewShelf()
    }
}

/// Carbon calls this on the main thread; `userData` is the `HotKeyCenter` that installed it.
private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, HotKeyCenter.isNewShelfHotKey(event) else { return OSStatus(eventNotHandledErr) }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { center.hotKeyPressed() }
    return noErr
}
