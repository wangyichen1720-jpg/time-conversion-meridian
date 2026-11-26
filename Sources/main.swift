import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = Model()
    private let popover = NSPopover()
    private var status: NSStatusItem!
    private var keyMonitor: Any?
    private var chooser: NSOpenPanel?
    private var host: NSHostingController<Interface>!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenus()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = status.button else { return }
        let icon = NSImage(systemSymbolName:"clock.arrow.2.circlepath", accessibilityDescription:"Meridian time converter") ?? NSImage(systemSymbolName:"clock", accessibilityDescription:"Meridian")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "Meridian · Click to convert a time, or drop a screenshot"
        button.target = self; button.action = #selector(toggle)
        let target = DropTarget(frame: button.bounds)
        target.autoresizingMask = [.width,.height]; target.toolTip = button.toolTip
        target.setAccessibilityElement(true); target.setAccessibilityRole(.button); target.setAccessibilityLabel("Meridian time converter")
        target.clicked = { [weak self] in self?.toggle() }
        target.contextAction = { [weak self, weak target] in
            guard let self, let target else { return }
            let menu = NSMenu()
            for (title,action) in [("Open Meridian",#selector(self.show)),("Settings…",#selector(self.settings)),("Quit Meridian",#selector(self.quit))] {
                let entry = menu.addItem(withTitle:title,action:action,keyEquivalent:""); entry.target = self
            }
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

        host = NSHostingController(rootView:Interface(model:model))
        popover.contentViewController = host; popover.contentSize = Interface.size
        popover.behavior = .applicationDefined; popover.animates = false; popover.delegate = self
        model.chooseFile = { [weak self] in self?.openFile() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] e in
            guard let self, self.popover.isShown, self.chooser == nil else { return e }
            if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers?.lowercased() == "v", self.model.page == .converter {
                if Model.hasImage(.general) || !(self.host.view.window?.firstResponder is NSTextView) {
                    self.model.paste(); return nil
                }
            }
            return e
        }
        NotificationCenter.default.addObserver(self, selector:#selector(clockChanged), name:.NSSystemTimeZoneDidChange, object:nil)
        NotificationCenter.default.addObserver(self, selector:#selector(clockChanged), name:.NSCalendarDayChanged, object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector:#selector(clockChanged), name:NSWorkspace.didWakeNotification, object:nil)
        DispatchQueue.main.async { self.show() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows flag:Bool) -> Bool { show(); return true }
    @objc private func clockChanged() { model.recalculate() }
    @objc func show() {
        guard let button = status?.button else { return }
        if let chooser { chooser.makeKeyAndOrderFront(nil); return }
        if !popover.isShown {
            model.recalculate()
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        }
        NSApp.activate(ignoringOtherApps:true)
        host.view.window?.makeKeyAndOrderFront(nil)
    }
    @objc func toggle() {
        if popover.isShown {
            popover.close()
            chooser?.cancel(nil)
        } else {
            show()
        }
    }
    // AppKit consults this for implicit dismissals. Only the status item calls close() directly.
    func popoverShouldClose(_ popover: NSPopover) -> Bool { false }
    @objc func settings() { model.page = .settings; show() }
    @objc func quit() { NSApp.terminate(nil) }
    func popoverDidShow(_ notification:Notification) {
        host.view.window?.hidesOnDeactivate = false
        host.view.window?.level = .floating
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
        panel.prompt = "Read image"
        NSApp.activate(ignoringOtherApps:true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.chooser = nil
            if self.popover.isShown { self.host.view.window?.makeKeyAndOrderFront(nil) }
            if response == .OK, let url = panel.url { self.model.read(.file(url), name:url.lastPathComponent) }
        }
    }
    private func installMenus() {
        let bar = NSMenu()
        let app = NSMenu(); app.addItem(withTitle:"Quit Meridian",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
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
