import AppKit
import Carbon
import CapletCore
import UniformTypeIdentifiers

/// The Settings window: a keyboard showing what ⇪ (or ⌥⇪) and each key does, where clicking a
/// key changes it, plus the general options underneath.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let cyclingKey = "cycleSizes"

    var keymap: Keymap {
        didSet {
            keyboard.keymap = keymap
            restoreButton.isEnabled = keymap != .defaults
        }
    }
    private let onChange: (Keymap) -> Void
    private let keyboard: KeyboardView
    private let hint = NSTextField(labelWithString: "")
    private let cycleBox = NSButton(checkboxWithTitle: "Cycle sizes on repeated presses", target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let restoreButton = NSButton(title: "Restore Defaults", target: nil, action: nil)
    private var monitor: Any?

    init(keymap: Keymap, onChange: @escaping (Keymap) -> Void) {
        self.keymap = keymap
        self.onChange = onChange
        keyboard = KeyboardView(keymap: keymap)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Caplet Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        keyboard.onChange = { [weak self] keymap in self?.change(keymap) }
        keyboard.onLayerChange = { [weak self] in self?.updateHint() }

        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.alignment = .center

        cycleBox.target = self
        cycleBox.action = #selector(toggleCycling)
        loginBox.target = self
        loginBox.action = #selector(toggleLaunchAtLogin)
        loginBox.allowsMixedState = true
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaults)
        restoreButton.isEnabled = keymap != .defaults

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [cycleBox, loginBox, spacer, restoreButton])
        footer.spacing = 20
        let separator = NSBox()
        separator.boxType = .separator

        let content = NSStackView(views: [keyboard, hint, separator, footer])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 14
        content.setCustomSpacing(20, after: hint)
        for view in [separator, footer] {
            view.widthAnchor.constraint(equalTo: keyboard.widthAnchor).isActive = true
        }
        // A stack view's edgeInsets give way when the window sizes itself to fit, so the margins
        // are pinned with required constraints instead.
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        window.contentView = container
        window.setContentSize(container.fittingSize)
        updateHint()

        // Keys light up on the drawing while held, like Keyboard Viewer; ⌥ shows the ⌥⇪ layer.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// Returns true to swallow the event.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let code = Int(event.keyCode)
        switch event.type {
        case .flagsChanged:
            keyboard.optionHeld = event.modifierFlags.contains(.option)
            keyboard.modifiersChanged(event.modifierFlags)
            return false
        case .keyUp:
            keyboard.release(code)
            return true
        default:
            break
        }
        if !event.isARepeat { keyboard.press(code) }
        if event.modifierFlags.contains(.command) {
            // The app has no main menu, so ⌘W needs handling here.
            guard event.charactersIgnoringModifiers == "w" else { return false }
            window?.performClose(nil)
            return true
        }
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        keyboard.shape = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO ? .iso : .ansi
        cycleBox.state = UserDefaults.standard.object(forKey: Self.cyclingKey) as? Bool ?? true ? .on : .off
        updateLoginBox()
        if window?.isVisible != true { window?.center() }
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        keyboard.optionHeld = false
        keyboard.releaseAll()
    }

    private func change(_ keymap: Keymap) {
        self.keymap = keymap
        onChange(keymap)
    }

    private func updateHint() {
        switch (keyboard.shownLayer, keyboard.optionLatched) {
        case (.caps, _):
            hint.stringValue = "Click a key to change what ⇪ and that key do. Press a key to find it. Hold or click ⌥ for ⌥⇪."
        case (.option, false):
            hint.stringValue = "Showing ⌥⇪ shortcuts. Release ⌥ to go back to ⇪."
        case (.option, true):
            hint.stringValue = "Showing ⌥⇪ shortcuts. Click ⌥ to go back to ⇪."
        }
    }

    private func updateLoginBox() {
        let state = LoginItem.state
        loginBox.isEnabled = state != .unavailable
        switch state {
        case .enabled: loginBox.state = .on
        case .requiresApproval: loginBox.state = .mixed
        case .disabled, .unavailable: loginBox.state = .off
        }
        switch state {
        case .requiresApproval: loginBox.toolTip = "Switched off in System Settings › Login Items. Click to open it."
        case .unavailable: loginBox.toolTip = "Launch at login needs Caplet.app, not swift run."
        case .enabled, .disabled: loginBox.toolTip = nil
        }
    }

    @objc private func toggleCycling() {
        UserDefaults.standard.set(cycleBox.state == .on, forKey: Self.cyclingKey)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch LoginItem.state {
            // Registering again won't help; only the user can flip it back on.
            case .requiresApproval: LoginItem.openSystemSettings()
            case .enabled: try LoginItem.setEnabled(false)
            case .disabled: try LoginItem.setEnabled(true)
            case .unavailable: break
            }
        } catch {
            NSLog("Caplet: %@", String(describing: error))
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change launch at login"
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) }
        }
        updateLoginBox()
    }

    @objc private func restoreDefaults() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Restore the default shortcuts?"
        alert.informativeText = "Window shortcuts go back to their original keys, in both layers, and app shortcuts are removed."
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.change(.defaults) }
        }
    }
}

/// Draws the keyboard. Bound keys are filled and show their command's icon; free keys are
/// outlines. Clicking a free or bound key opens a menu of everything it can do.
@MainActor
final class KeyboardView: NSView {
    var keymap: Keymap { didSet { images = [:]; needsDisplay = true } }
    var shape: KeyboardShape = .ansi {
        didSet { if shape != oldValue { keys = Keyboard.keys(shape); needsDisplay = true } }
    }
    var optionHeld = false { didSet { if optionHeld != oldValue { layerChanged() } } }
    private(set) var optionLatched = false
    var shownLayer: HyperLayer { optionHeld || optionLatched ? .option : .caps }
    var onChange: ((Keymap) -> Void)?
    var onLayerChange: (() -> Void)?

    private var keys = Keyboard.keys(.ansi)
    private var images: [HyperCommand: NSImage] = [:]
    private var hovered: Int?
    /// The key whose menu is open.
    private var editing: Int?
    /// Key codes held down on the keyboard.
    private var held: Set<Int> = []

    private static let unit: CGFloat = 52
    private static let gap: CGFloat = 6
    /// The same for every key, whatever its size, like Keyboard Viewer.
    private static let radius: CGFloat = 6
    /// Device-dependent bits of `NSEvent.modifierFlags` for each modifier key, so left and right
    /// Shift (and the rest) light up on their own.
    private static let modifierBits: [Int: UInt] = [
        0x38: 0x2, 0x3C: 0x4, 0x3B: 0x1, 0x3E: 0x2000, 0x3A: 0x20, 0x3D: 0x40, 0x37: 0x8, 0x36: 0x10,
    ]

    init(keymap: Keymap) {
        self.keymap = keymap
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Keyboard.width * Self.unit, height: Keyboard.height * Self.unit)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                              .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    func press(_ code: Int) {
        guard !held.contains(code) else { return }
        held.insert(code)
        needsDisplay = true
    }

    func release(_ code: Int) {
        guard held.remove(code) != nil else { return }
        needsDisplay = true
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        for (code, bit) in Self.modifierBits {
            if flags.rawValue & bit != 0 { press(code) } else { release(code) }
        }
        if flags.contains(.function) { press(0x3F) } else { release(0x3F) }
        // macOS often sends no key-up for a key typed with ⌘ held, so letting go of ⌘ releases it.
        if !flags.contains(.command) {
            for code in held where Self.modifierBits[code] == nil && code != 0x3F { release(code) }
        }
    }

    func releaseAll() {
        for code in held { release(code) }
    }

    private func layerChanged() {
        needsDisplay = true
        onLayerChange?()
    }

    // MARK: Drawing

    // Muted like Keyboard Viewer: every key has the same thin outline, keys with a shortcut add a
    // neutral fill, and active keys (Caps Lock, ⌥ in the ⌥⇪ layer, keys held down, the key being
    // edited) only get a faint accent tint and an accent outline.
    override func draw(_ dirtyRect: NSRect) {
        for (index, key) in keys.enumerated() {
            let path = self.path(for: key)
            var active: CGFloat = key.keyCode.map(held.contains) == true ? 1 : 0
            var command: HyperCommand?
            var symbol: String?
            switch key.kind {
            case .bindable(let code):
                command = keymap[shownLayer, code]
                if command != nil {
                    NSColor.labelColor.withAlphaComponent(0.1).setFill()
                    path.fill()
                }
                if editing == index { active = 1 }
            case .capsLock:
                active = 1
                symbol = "capslock"
            case .option:
                if shownLayer == .option { active = 1 }
                symbol = "option"
            case .isoReturn, .fixed:
                symbol = Self.symbolName(for: key.kind)
            }
            if hovered == index {
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                path.fill()
            }
            if active > 0 {
                NSColor.controlAccentColor.withAlphaComponent(0.2 * active).setFill()
                path.fill()
            }
            NSColor.tertiaryLabelColor.blended(withFraction: active, of: .controlAccentColor)?.setStroke()
            path.lineWidth = 1
            stroke(path)
            if let command { drawIcon(for: command, in: path.bounds) }
            if let symbol {
                let color: NSColor = key.kind == .capsLock || active > 0.5 ? .labelColor : .tertiaryLabelColor
                drawSymbol(symbol, in: path.bounds, color: color)
            }
        }
    }

    private static func symbolName(for kind: KeyCap.Kind) -> String {
        switch kind {
        case .fixed(.delete, _): return "delete.left"
        case .fixed(.tab, _): return "arrow.right.to.line"
        case .fixed(.returnKey, _), .isoReturn: return "return"
        case .fixed(.shift, _): return "shift"
        case .fixed(.function, _): return "globe"
        case .fixed(.control, _): return "control"
        case .fixed(.command, _): return "command"
        case .bindable, .capsLock, .option: return ""
        }
    }

    /// Strokes inside the path, so outlines and filled keys line up.
    private func stroke(_ path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let width = path.lineWidth
        path.lineWidth = width * 2
        path.stroke()
        path.lineWidth = width
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawIcon(for command: HyperCommand, in rect: NSRect) {
        if case .launch = command {
            let side = min(rect.width, rect.height) * 0.72
            let image = images[command] ?? command.image
            images[command] = image
            image?.draw(in: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        let image = images[command] ?? command.image.flatMap { image in
            let size = min(rect.width, rect.height) * 0.4
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
            return image.withSymbolConfiguration(config)
        }
        images[command] = image
        guard let image else { return }
        image.draw(in: NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: Self.unit * 0.3, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        // ISO Return's glyph goes in its upper, wider half.
        let center = NSPoint(x: rect.midX, y: rect.height > Self.unit * 1.5 ? rect.minY + (Self.unit - Self.gap) / 2 : rect.midY)
        let origin = NSPoint(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2)
        image.draw(in: NSRect(origin: origin, size: image.size), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
    }

    private func path(for key: KeyCap) -> NSBezierPath {
        let unit = bounds.width / Keyboard.width
        let inset = Self.gap / 2
        let rect = NSRect(x: key.x * unit, y: key.y * unit, width: key.width * unit, height: key.height * unit)
            .insetBy(dx: inset, dy: inset)
        let radius = Self.radius
        guard key.kind == .isoReturn else { return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
        // The lower half starts a quarter key further right.
        let notchX = rect.minX + unit / 4
        let notchY = key.y * unit + unit - inset
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: notchX, y: rect.maxY),
            NSPoint(x: notchX, y: notchY), NSPoint(x: rect.minX, y: notchY),
        ]
        let path = NSBezierPath()
        path.move(to: NSPoint(x: (corners[5].x + corners[0].x) / 2, y: (corners[5].y + corners[0].y) / 2))
        for index in corners.indices {
            path.appendArc(from: corners[index], to: corners[(index + 1) % corners.count], radius: radius)
        }
        path.close()
        return path
    }

    // MARK: Mouse

    private func key(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return keys.indices.first { path(for: keys[$0]).contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let index = key(at: event).flatMap { index -> Int? in
            switch keys[index].kind {
            case .bindable, .option: return index
            default: return nil
            }
        }
        if index != hovered {
            hovered = index
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = key(at: event) else { return }
        switch keys[index].kind {
        case .bindable(let code): showMenu(forKeyAt: index, code: code)
        case .option:
            optionLatched.toggle()
            layerChanged()
        default: break
        }
    }

    // MARK: Menu

    /// The choice a menu item stands for: `command` nil clears the key.
    private struct Choice {
        var layer: HyperLayer
        var keyCode: Int
        var command: HyperCommand?
    }

    private func showMenu(forKeyAt index: Int, code: Int) {
        // The menu edits the layer shown when it opened, even if ⌥ is let go meanwhile.
        let layer = shownLayer
        let current = keymap[layer, code]
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ command: HyperCommand?, image: NSImage? = nil) {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.image = image
            item.state = command == current ? .on : .off
            item.representedObject = Choice(layer: layer, keyCode: code, command: command)
            menu.addItem(item)
        }

        add("None", nil)
        menu.addItem(.separator())
        menu.addItem(.header("Window"))
        for action in TileAction.allCases { add(action.title, .tile(action), image: HyperCommand.tile(action).image) }
        menu.addItem(.separator())
        menu.addItem(.header("Arrange"))
        for action in ArrangeAction.allCases {
            add(action.title, .arrange(action), image: HyperCommand.arrange(action).image)
        }
        menu.addItem(.separator())
        menu.addItem(.header("App"))
        if let current, case .launch = current {
            let icon = current.image
            icon?.size = NSSize(width: 16, height: 16)
            add(current.title, current, image: icon)
        }
        let choose = NSMenuItem(title: "Choose Application…", action: #selector(chooseApplication(_:)), keyEquivalent: "")
        choose.target = self
        choose.representedObject = Choice(layer: layer, keyCode: code, command: nil)
        menu.addItem(choose)

        editing = index
        hovered = nil
        needsDisplay = true
        let rect = path(for: keys[index]).bounds
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + 4), in: self)
        editing = nil
        needsDisplay = true
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice else { return }
        set(choice)
    }

    @objc private func chooseApplication(_ sender: NSMenuItem) {
        guard var choice = sender.representedObject as? Choice else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose the app that \(choice.layer.symbol) and this key open."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            NSSound.beep()
            return
        }
        choice.command = .launch(bundleID)
        set(choice)
    }

    private func set(_ choice: Choice) {
        var keymap = self.keymap
        keymap[choice.layer, choice.keyCode] = choice.command
        guard keymap != self.keymap else { return }
        self.keymap = keymap
        onChange?(keymap)
    }
}

extension NSMenuItem {
    static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
