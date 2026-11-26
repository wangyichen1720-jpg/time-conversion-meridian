import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = Model()
    private let popover = NSPopover()
    private var status: NSStatusItem!
    private let iconAnchor = NSView()
    private var menuFace: MenuClockFace?
    private var naturalClockImage: NSImage?
    private var layoutQueued = false
    private weak var statusDropTarget: DropTarget?
    private var minuteTimer: Timer?
    private var clockObservation: AnyCancellable?
    private var keyMonitor: Any?
    private var chooser: NSOpenPanel?
    private var host: NSHostingController<Interface>!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenus()
        // Give new installs room near the system clock. AppKit's saved user placement takes precedence.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position MeridianClock": 160.0])
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = status.button else { return }
        status.autosaveName = "MeridianClock"
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.addSubview(iconAnchor)
        iconAnchor.setAccessibilityElement(false)
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(positionIconAnchor),
                                               name: NSView.frameDidChangeNotification, object: button)
        button.target = self; button.action = #selector(toggle)
        let target = DropTarget(frame: button.bounds)
        target.autoresizingMask = [.width,.height]
        target.setAccessibilityElement(true); target.setAccessibilityRole(.button); target.setAccessibilityLabel("Meridian time converter")
        target.clicked = { [weak self] in self?.toggle() }
        target.contextAction = { [weak self, weak target] in
            guard let self, let target else { return }
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Meridian", action: #selector(self.openConverter), keyEquivalent: "").target = self
            self.addAppCommands(to: menu)
            menu.popUp(positioning:nil,at:NSPoint(x:0,y:0),in:target)
        }
        target.receive = { [weak self] pb in
            guard let self else { return false }
            self.model.page = .converter
            self.show()
            return self.model.accept(pb)
        }
        target.hoverChanged = { [weak button] in button?.highlight($0) }
        button.addSubview(target)
        statusDropTarget = target
        if let window = button.window {
            for notice in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(positionIconAnchor), name: notice, object: window)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(positionIconAnchor),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startMenuClock()
        clockObservation = Publishers.CombineLatest4(model.$destination, model.$showDetectedClock, model.$report, model.$index)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuClock() }

        host = NSHostingController(rootView:Interface(model:model))
        popover.contentViewController = host; popover.contentSize = Interface.size
        popover.behavior = .applicationDefined; popover.animates = false; popover.delegate = self
        model.chooseFile = { [weak self] in self?.openFile() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] e in
            guard let self, self.popover.isShown, self.chooser == nil else { return e }
            let modifiers = e.modifierFlags.intersection([.command, .control, .shift, .option])
            if self.model.page != .converter && e.window === self.host.view.window {
                let composing = (e.window?.firstResponder as? NSTextView)?.hasMarkedText() == true
                if !composing && ((e.keyCode == 53 && modifiers.isEmpty) ||
                    (e.charactersIgnoringModifiers == "[" && modifiers == .command)) {
                    self.model.goBack()
                    return nil
                }
            }
            if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers?.lowercased() == "v", self.model.page == .converter {
                if Model.hasImage(.general) || !(self.host.view.window?.firstResponder is NSTextView) {
                    self.model.paste(); return nil
                }
            }
            return e
        }
        NotificationCenter.default.addObserver(self, selector:#selector(clockChanged), name:.NSSystemTimeZoneDidChange, object:nil)
        NotificationCenter.default.addObserver(self, selector:#selector(clockChanged), name:.NSSystemClockDidChange, object:nil)
        NotificationCenter.default.addObserver(self, selector:#selector(clockChanged), name:.NSCalendarDayChanged, object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector:#selector(clockChanged), name:NSWorkspace.didWakeNotification, object:nil)
        DispatchQueue.main.async { self.show() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows flag:Bool) -> Bool { show(); return true }
    private func updateMenuClock(at date: Date = Date()) {
        guard let button = status?.button else { return }
        let zone = model.target
        let chosen = MenuClockFace.line(Zones.menuName(zone.identifier), date: date, in: zone)
        var detected: String?
        var description = "Meridian · " + Zones.displayName(Zones.label(zone.identifier), in: zone, at: date) + " · " + chosen
        if model.showDetectedClock, let hit = model.current, !hit.usesDefaultZone {
            detected = MenuClockFace.line(hit.menuZoneName, date: date, in: hit.source.zone)
            description += "\nDetected zone · " + Zones.displayName(hit.source.label, in: hit.source.zone, at: date) + " · " + (detected ?? "")
        }
        let face = MenuClockFace(chosen: chosen, detected: detected)
        if face != menuFace {
            menuFace = face
            naturalClockImage = face.image()
            fitClockToMenuBar(refresh: true)
            positionIconAnchor()
        }
        button.toolTip = description + "\nClick to convert a time, or drop a screenshot."
        button.setAccessibilityLabel(description)
        statusDropTarget?.toolTip = button.toolTip
        statusDropTarget?.setAccessibilityLabel(description)
    }

    private func fitClockToMenuBar(refresh: Bool = false) {
        guard let button = status?.button, let face = menuFace, let natural = naturalClockImage else { return }
        var width = natural.size.width
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let region = screen?.auxiliaryTopRightArea {
            // A hidden status window can have stale geometry until it fits beside the notch.
            // Start with a compact face even before Control Center supplies a usable frame.
            if let frame = button.window?.frame, frame.maxX > region.minX, frame.maxX <= region.maxX {
                width = min(width, max(MenuClockFace.iconWidth, floor(frame.maxX - region.minX) - 38))
            } else {
                width = min(width, 78)
            }
        }
        if refresh || button.image?.size.width != width {
            button.image = width == natural.size.width ? natural : face.image(maxWidth: width)
        }
    }

    @objc private func positionIconAnchor() {
        guard let button = status?.button, let image = button.image else { return }
        let left = max(button.bounds.minX, button.bounds.midX - image.size.width / 2)
        iconAnchor.frame = NSRect(x: left, y: button.bounds.minY,
                                  width: MenuClockFace.iconWidth, height: button.bounds.height)
        guard !layoutQueued else { return }
        layoutQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutQueued = false
            self.fitClockToMenuBar()
            self.alignOpenPanel()
        }
    }

    private func alignOpenPanel() {
        guard popover.isShown, let menuWindow = iconAnchor.window, let panel = host.view.window,
              let screen = menuWindow.screen else { return }
        let icon = menuWindow.convertToScreen(iconAnchor.convert(iconAnchor.bounds, to: nil))
        guard screen.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) else { return }
        let visible = screen.visibleFrame
        let centered = (icon.midX - panel.frame.width / 2).rounded()
        let x = max(visible.minX, min(centered, visible.maxX - panel.frame.width))
        let top = min(visible.maxY, menuWindow.frame.minY)
        let y = max(visible.minY, top - panel.frame.height)
        let origin = NSPoint(x: x, y: y)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func startMenuClock() {
        minuteTimer?.invalidate()
        let now = Date()
        updateMenuClock(at: now)
        let nextMinute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            self?.updateMenuClock()
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    @objc private func clockChanged() {
        startMenuClock()
        model.recalculate()
    }
    @objc func show() {
        guard iconAnchor.window != nil else { return }
        if let chooser { chooser.makeKeyAndOrderFront(nil); return }
        if !popover.isShown {
            model.recalculate()
            positionIconAnchor()
            popover.show(relativeTo: .zero, of: iconAnchor, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps:true)
        host.view.window?.makeKeyAndOrderFront(nil)
    }
    @objc func toggle() {
        if popover.isShown {
            popover.close()
            let activeChooser = chooser
            chooser = nil
            activeChooser?.cancel(nil)
        } else {
            show()
        }
    }
    // AppKit consults this for implicit dismissals. Only the status item calls close() directly.
    func popoverShouldClose(_ popover: NSPopover) -> Bool { false }
    @objc func openConverter() { model.page = .converter; show() }
    @objc func settings() { model.page = .settings; show() }
    @objc func quit() { NSApp.terminate(nil) }
    func popoverDidShow(_ notification:Notification) {
        host.view.window?.hidesOnDeactivate = false
        host.view.window?.level = .floating
        alignOpenPanel()
        guard model.page == .converter else { return }
        func find(_ view:NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            for subview in view.subviews { if let match = find(subview) { return match } }
            return nil
        }
        if let editor = find(host.view) { host.view.window?.makeFirstResponder(editor) }
    }
    private func openFile() {
        if let chooser { chooser.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel(); chooser = panel
        panel.level = .modalPanel
        panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Choose an Image"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps:true)
        panel.begin { [weak self] response in
            guard let self, self.chooser === panel else { return }
            self.chooser = nil
            self.show()
            if response == .OK, let url = panel.url { self.model.read(.file(url), name:url.lastPathComponent) }
        }
        panel.makeKeyAndOrderFront(nil)
    }
    private func addAppCommands(to menu: NSMenu) {
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meridian", action: #selector(quit), keyEquivalent: "q").target = self
    }
    private func installMenus() {
        let bar = NSMenu()
        let app = NSMenu(title: "Meridian"); addAppCommands(to: app)
        let appItem = NSMenuItem(); appItem.submenu = app; bar.addItem(appItem)
        let edit = NSMenu(title:"Edit")
        for (title,action,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            edit.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; bar.addItem(editItem); NSApp.mainMenu = bar
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
