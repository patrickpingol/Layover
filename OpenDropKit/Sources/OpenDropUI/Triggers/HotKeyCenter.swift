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
    /// A combo another app already registered is left unregistered.
    public func register(_ combo: KeyCombo?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let combo else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, Self.hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr { hotKeyRef = ref }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
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
