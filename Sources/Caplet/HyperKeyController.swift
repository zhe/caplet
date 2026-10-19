import AppKit
import CapletCore
import IOKit

/// Caps Lock as a hyper key: hidutil remaps Caps Lock to F18, and a keyboard event tap
/// treats F18 as held-down modifier, swallowing the bound keys pressed while it is down.
/// Tapping F18 on its own toggles the real Caps Lock state, so capitals still work.
/// Active event taps need the same Accessibility permission the window mover uses.
@MainActor
final class HyperKeyController {
    enum State: Equatable {
        case off
        case waitingForAccessibility
        case active
        /// Another app remapped Caps Lock after Caplet did. Holds the key it sends now, if known.
        case takenOver(String?)
        case failed(String)
    }

    private(set) var state: State = .off {
        didSet { if state != oldValue { onStateChange?() } }
    }
    var onStateChange: (@MainActor () -> Void)?
    private let onCommand: @MainActor (HyperCommand) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var capsTap = CapsTap()
    private var displacedMapping: KeyMapping?
    private var wakeObserver: NSObjectProtocol?
    private var keyboardPort: IONotificationPortRef?
    private var keyboardIterator: io_iterator_t = 0
    private var checkTimer: Timer?

    init(onCommand: @escaping @MainActor (HyperCommand) -> Void) {
        self.onCommand = onCommand
    }

    func start() {
        guard tap == nil else { return }
        guard installTap() else {
            state = .waitingForAccessibility
            scheduleRetry()
            return
        }
        guard let current = HIDUtil.currentMappings() else {
            removeTap()
            state = .failed("Couldn't read key remaps from hidutil")
            return
        }
        let change = HyperRemap.enabling(current)
        guard HIDUtil.set(change.mappings) else {
            removeTap()
            state = .failed("Couldn't remap Caps Lock with hidutil")
            return
        }
        displacedMapping = change.displaced
        state = .active
        watchKeyboards()
    }

    /// Puts Caps Lock → F18 back on keyboards that lost it, such as one plugged in later, but
    /// leaves another app's Caps Lock remap alone: overwriting it would start a tug-of-war
    /// that each wake decides. `takeBack()` does that when the user asks.
    func recheck() {
        switch state {
        case .active, .takenOver: break
        case .off, .waitingForAccessibility, .failed: return
        }
        guard let keyboards = HIDUtil.keyboardMappings() else { return }
        switch HyperRemap.check(keyboards: keyboards) {
        case .intact:
            state = .active
        case .missing:
            state = reapply() ? .active : .failed("Couldn't remap Caps Lock with hidutil")
        case .taken(let key):
            state = .takenOver(HyperRemap.keyName(key))
        }
    }

    func takeBack() {
        guard case .takenOver = state else { return }
        if reapply() { recheck() }
    }

    private var capsLockTakenOver: Bool {
        guard let keyboards = HIDUtil.keyboardMappings(),
              case .taken = HyperRemap.check(keyboards: keyboards) else { return false }
        return true
    }

    /// Keeps `displacedMapping`: a remap taken back belongs to another app, not to the user.
    private func reapply() -> Bool {
        guard let current = HIDUtil.currentMappings() else { return false }
        return HIDUtil.set(HyperRemap.enabling(current).mappings)
    }

    /// Removes the tap and gives Caps Lock back. Must run before quitting, otherwise
    /// Caps Lock stays remapped to F18 until logout.
    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        guard tap != nil else {
            state = .off
            return
        }
        removeTap()
        stopWatchingKeyboards()
        if let current = HIDUtil.currentMappings() {
            // An app that took Caps Lock since owns it now: keep its remap, not the one Caplet displaced.
            HIDUtil.set(HyperRemap.disabling(current, restoring: capsLockTakenOver ? nil : displacedMapping))
        }
        displacedMapping = nil
        state = .off
    }

    /// The built-in keyboard can come back after sleep without the remap, and other apps
    /// with a hyper key reapply theirs on wake, so check after waking and whenever a
    /// keyboard appears. The delay lets those apps finish first.
    private func watchKeyboards() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }

        guard let matching = IOServiceMatching("IOHIDEventService"),
              let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                           .commonModes)
        (matching as NSMutableDictionary)["IOPropertyMatch"] = ["PrimaryUsagePage": 1, "PrimaryUsage": 6]
        guard IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, keyboardAppeared,
                                               Unmanaged.passUnretained(self).toOpaque(),
                                               &keyboardIterator) == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        keyboardPort = port
        // Draining arms the notification. The keyboards already there got the remap in start().
        drain(keyboardIterator)
    }

    private func stopWatchingKeyboards() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if keyboardIterator != 0 { IOObjectRelease(keyboardIterator) }
        keyboardIterator = 0
        if let keyboardPort { IONotificationPortDestroy(keyboardPort) }
        keyboardPort = nil
        checkTimer?.invalidate()
        checkTimer = nil
    }

    fileprivate func scheduleCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkTimer = nil
                self?.recheck()
            }
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.start()
            }
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: hyperTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        capsTap.reset()
    }

    /// Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The F18 key-up may have been lost while disabled; never leave W A S D hijacked.
            capsTap.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let now = ProcessInfo.processInfo.systemUptime
            if keyCode == HyperBindings.triggerKeyCode {
                if type == .keyDown {
                    capsTap.pressed(at: now)
                } else if capsTap.released(at: now) {
                    // Off the tap callback, like window actions below.
                    Task { @MainActor in CapsLockState.toggle() }
                }
                return true
            }
            guard capsTap.isHeld else { return false }
            if type == .keyDown { capsTap.otherKeyPressed() }
            let option = event.flags.contains(.maskAlternate)
            guard let command = HyperBindings.command(forKeyCode: keyCode, option: option) else { return false }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if type == .keyDown, !isRepeat {
                // Run after returning: a slow Accessibility call inside the tap would get it disabled.
                Task { @MainActor [weak self] in self?.onCommand(command) }
            }
            return true
        default:
            return false
        }
    }
}

private func drain(_ iterator: io_iterator_t) {
    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
}

private func keyboardAppeared(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    drain(iterator)
    guard let refcon else { return }
    let controller = Unmanaged<HyperKeyController>.fromOpaque(refcon).takeUnretainedValue()
    // The notification port's run loop source is on the main run loop.
    MainActor.assumeIsolated { controller.scheduleCheck() }
}

private func hyperTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HyperKeyController>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { controller.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

enum HIDUtil {
    static func currentMappings() -> [KeyMapping]? {
        run(["property", "--get", "UserKeyMapping"]).map(HyperRemap.parse)
    }

    /// The remaps of each keyboard, leaving out trackpads, sensors and other HID services.
    static func keyboardMappings() -> [[KeyMapping]]? {
        run(["property", "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}",
             "--get", "UserKeyMapping"]).map(HyperRemap.parseServices)
    }

    @discardableResult
    static func set(_ mappings: [KeyMapping]) -> Bool {
        run(["property", "--set", HyperRemap.json(mappings)]) != nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
