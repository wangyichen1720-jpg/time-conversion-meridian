import AppKit

struct MenuClockFace: Equatable {
    let chosen: String
    let detected: String?

    static let iconWidth: CGFloat = 16

    static func line(_ zoneName: String, date: Date, in zone: TimeZone) -> String {
        zoneName + "·" + Model.format(date, "MMM d HH:mm", zone)
    }

    var image: NSImage {
        let compact = detected != nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: compact ? 10 : 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let rows = [chosen, detected].compactMap { $0 }.map { NSAttributedString(string: $0, attributes: attributes) }
        let textX = Self.iconWidth + 4
        let width = ceil(rows.map { $0.size().width }.max() ?? 0)
        let height: CGFloat = 22
        let result = NSImage(size: NSSize(width: textX + width, height: height), flipped: false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: 4, width: 14, height: 14))
            ring.lineWidth = 1.6
            ring.stroke()
            let hands = NSBezierPath()
            hands.lineWidth = 1.5
            hands.lineCapStyle = .round
            hands.move(to: NSPoint(x: 8, y: 15.6))
            hands.line(to: NSPoint(x: 8, y: 11))
            hands.line(to: NSPoint(x: 11.6, y: 9))
            hands.stroke()

            let rowHeight = height / CGFloat(rows.count)
            for (index, row) in rows.enumerated() {
                // Position the baseline by cap height so both rows fit the 22-point menu bar.
                let centerY = height - (CGFloat(index) + 0.5) * rowHeight
                let baseline = centerY - font.capHeight / 2
                let line = CTLineCreateWithAttributedString(row)
                if let context = NSGraphicsContext.current?.cgContext {
                    context.textPosition = CGPoint(x: textX, y: baseline)
                    CTLineDraw(line, context)
                }
            }
            return true
        }
        result.isTemplate = true
        result.accessibilityDescription = [chosen, detected].compactMap { $0 }.joined(separator: ", ")
        return result
    }
}
