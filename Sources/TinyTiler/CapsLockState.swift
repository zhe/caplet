import IOKit
import IOKit.hidsystem

/// Reads and flips the system Caps Lock state through IOHIDSystem, the same state the
/// physical key toggles. The keyboard light follows it.
enum CapsLockState {
    private static let paramConnectType: UInt32 = 1 // kIOHIDParamConnectType
    private static let capsLockSelector: Int32 = 1 // kIOHIDCapsLockState

    @discardableResult
    static func toggle() -> Bool {
        withConnection { connect in
            var isOn = false
            guard IOHIDGetModifierLockState(connect, capsLockSelector, &isOn) == KERN_SUCCESS else { return false }
            return IOHIDSetModifierLockState(connect, capsLockSelector, !isOn) == KERN_SUCCESS
        } ?? false
    }

    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, paramConnectType, &connect) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connect) }
        return body(connect)
    }
}
