import AppKit
import SwiftUI

private final class InputView: NSTextView {
    var pasteImage: (() -> Bool)?
    override func paste(_ sender: Any?) {
        if Model.hasImage(.general), pasteImage?() == true { return }
        super.pasteAsPlainText(sender)
    }

}

struct TimeEditor: NSViewRepresentable {
    @Binding var text: String
    var pasteImage: () -> Bool
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TimeEditor
        init(_ parent: TimeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = InputView()
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(width: 11, height: 8)
        editor.font = NSFont.systemFont(ofSize: 15)
        editor.textColor = NSColor(srgbRed:0.10,green:0.16,blue:0.14,alpha:1)
        editor.insertionPointColor = .systemGreen
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.setAccessibilityLabel("Time to convert")
        editor.delegate = context.coordinator; editor.pasteImage = pasteImage
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? InputView else { return }
        editor.pasteImage = pasteImage
        if editor.string != text { editor.string = text; editor.scrollRangeToVisible(NSRange(location:0,length:0)) }
    }
}

class DropTarget: NSView {
    var receive: ((NSPasteboard) -> Bool)?
    var clicked: (() -> Void)?
    var contextAction: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    override init(frame: NSRect) {
        super.init(frame:frame)
        registerForDraggedTypes(Model.dropTypes)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.control), let action = contextAction { action() } else { clicked?() }
    }
    override func rightMouseDown(with event:NSEvent) { contextAction?() }
    override func draggingEntered(_ sender:any NSDraggingInfo) -> NSDragOperation {
        let valid = Model.hasImage(sender.draggingPasteboard) || sender.draggingPasteboard.availableType(from:[.string]) != nil
        hoverChanged?(valid)
        return valid ? .copy : []
    }
    override func draggingExited(_ sender:(any NSDraggingInfo)?) { hoverChanged?(false) }
    override func prepareForDragOperation(_ sender:any NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender:any NSDraggingInfo) -> Bool {
        hoverChanged?(false); return receive?(sender.draggingPasteboard) ?? false
    }
    override func draggingEnded(_ sender:any NSDraggingInfo) { hoverChanged?(false) }
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor:.pointingHand) }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
}

struct DropArea: NSViewRepresentable {
    let model: Model
    func makeNSView(context: Context) -> DropTarget {
        let target = DropTarget(frame:.zero)
        target.wantsLayer = true; target.layer?.cornerRadius = 8
        target.hoverChanged = { [weak target] inside in
            target?.layer?.backgroundColor = inside ? NSColor.systemGreen.withAlphaComponent(0.16).cgColor : nil
        }
        target.clicked = { model.chooseFile?() }
        target.receive = { model.accept($0) }
        return target
    }
    func updateNSView(_ nsView:DropTarget, context:Context) {}
}
