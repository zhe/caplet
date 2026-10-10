import AppKit
import TilerCore

/// Caps Lock as a hyper key: hidutil remaps Caps Lock to F18, and a keyboard event tap
/// treats F18 as held-down modifier, swallowing the bound keys pressed while it is down.
/// Active event taps need the same Accessibility permission the window mover uses.
@MainActor
final class HyperKeyController {
    enum State: Equatable {
        case off
        case waitingForAccessibility
        case active
        case failed(String)
    }

    private(set) var state: State = .off
    private let onAction: @MainActor (TileAction) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var hyperDown = false
    private var displacedMapping: KeyMapping?

    init(onAction: @escaping @MainActor (TileAction) -> Void) {
        self.onAction = onAction
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
        if let current = HIDUtil.currentMappings() {
            HIDUtil.set(HyperRemap.disabling(current, restoring: displacedMapping))
        }
        displacedMapping = nil
        state = .off
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
        hyperDown = false
    }

    /// Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The F18 key-up may have been lost while disabled; never leave W A S D hijacked.
            hyperDown = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == HyperBindings.triggerKeyCode {
                hyperDown = type == .keyDown
                return true
            }
            guard hyperDown, let action = HyperBindings.action(forKeyCode: keyCode) else { return false }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if type == .keyDown, !isRepeat {
                // Run after returning: a slow Accessibility call inside the tap would get it disabled.
                Task { @MainActor [weak self] in self?.onAction(action) }
            }
            return true
        default:
            return false
        }
    }
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
