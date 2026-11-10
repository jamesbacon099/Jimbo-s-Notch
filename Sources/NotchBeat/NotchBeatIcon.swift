import AppKit

@MainActor
enum NotchBeatIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            let island = NSBezierPath(roundedRect: NSRect(x: 7.8, y: 5.6, width: 6.4, height: 4.8),
                                      xRadius: 2.4, yRadius: 2.4)
            island.lineWidth = 1.35
            island.stroke()

            let waves = NSBezierPath()
            waves.move(to: NSPoint(x: 0.9, y: 8))
            waves.curve(to: NSPoint(x: 6.0, y: 8), controlPoint1: NSPoint(x: 2.7, y: 8),
                        controlPoint2: NSPoint(x: 3.0, y: 13.3))
            waves.move(to: NSPoint(x: 16.0, y: 8))
            waves.curve(to: NSPoint(x: 21.1, y: 8), controlPoint1: NSPoint(x: 19, y: 2.7),
                        controlPoint2: NSPoint(x: 19.3, y: 8))
            waves.lineWidth = 1.45
            waves.lineCapStyle = .round
            waves.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotchBeat"
        return image
    }()
}
