import AppKit
import SwiftUI

/// Draws the menu bar icon for a state at animation time `t` (seconds).
///
/// Like Bluetooth & co., "idle" and "working" are monochrome template images
/// (macOS tints them for light/dark). It only turns colorful when you need to act.
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 18)

    /// - Parameters:
    ///   - t: seconds since app launch (for looping animations)
    ///   - sinceChange: seconds since the last state change (for pop/shake effects)
    static func image(for state: SessionState, t: Double, sinceChange: Double) -> NSImage {
        switch state {
        case .idle: return idle()
        case .working: return workingDots(t: t)
        case .needsInput: return wavingHand(t: t, sinceChange: sinceChange)
        case .done: return popSymbol("checkmark.circle.fill", color: NSColor(Theme.done), sinceChange: sinceChange)
        case .error: return shakeSymbol("exclamationmark.triangle.fill", color: NSColor(Theme.error), sinceChange: sinceChange)
        }
    }

    /// Is a looping animation needed (timer running)?
    static func isAnimated(_ state: SessionState, sinceChange: Double) -> Bool {
        switch state {
        case .working, .needsInput: true
        case .done, .error: sinceChange < 1.0
        case .idle: false
        }
    }

    // MARK: States

    /// Idle: a little radar blip – dot with a ring.
    private static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12))
            ring.lineWidth = 1.4
            NSColor.black.withAlphaComponent(0.55).setStroke()
            ring.stroke()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 2.6, y: rect.midY - 2.6, width: 5.2, height: 5.2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Working: three dots bouncing in a wave.
    private static func workingDots(t: Double) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let radius: CGFloat = 2.3
            let spacing: CGFloat = 6
            let startX = rect.midX - spacing
            for i in 0..<3 {
                let wave = max(0, sin(t * 7 - Double(i) * 0.8))
                let r = radius * (1 + 0.25 * wave)
                let x = startX + CGFloat(i) * spacing
                let y = rect.midY - 1.5 + 4 * wave
                NSColor.black.withAlphaComponent(0.55 + 0.45 * wave).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Needs you: an orange hand that waves every few seconds (immediately after the change).
    private static func wavingHand(t: Double, sinceChange: Double) -> NSImage {
        // One wave = 0.8 s with two back-and-forth swings.
        func wave(_ s: Double) -> Double { s < 0.8 ? sin(s / 0.8 * .pi * 4) * 20 : 0 }
        let angle = sinceChange < 1.6
            ? wave(sinceChange.truncatingRemainder(dividingBy: 0.8)) // right after the change: wave twice
            : wave(t.truncatingRemainder(dividingBy: 3.2))           // then once every 3.2 s
        let hop = sinceChange < 0.4 ? sin(sinceChange / 0.4 * .pi) * 3 : 0
        return draw(symbol: "hand.raised.fill", color: NSColor(Theme.waiting),
                    rotation: angle, scale: 1, offsetY: hop)
    }

    /// Done: a checkmark pops in with a little overshoot.
    private static func popSymbol(_ name: String, color: NSColor, sinceChange: Double) -> NSImage {
        let e = min(sinceChange, 1)
        let scale = e >= 1 ? 1 : 1 - exp(-7 * e) * cos(13 * e)
        return draw(symbol: name, color: color, rotation: 0, scale: max(0.05, scale), offsetY: 0)
    }

    /// Error: a quick head shake.
    private static func shakeSymbol(_ name: String, color: NSColor, sinceChange: Double) -> NSImage {
        let e = min(sinceChange, 1)
        let rotation = e >= 1 ? 0 : sin(e * .pi * 8) * 14 * (1 - e)
        return draw(symbol: name, color: color, rotation: rotation, scale: 1, offsetY: 0)
    }

    // MARK: Helpers

    private static func symbol(_ name: String, pointSize: CGFloat, color: NSColor? = nil) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        if let color { config = config.applying(.init(paletteColors: [color])) }
        return NSImage(systemSymbolName: name, accessibilityDescription: "Blip")?.withSymbolConfiguration(config)
    }

    private static func draw(symbol name: String, color: NSColor, rotation: Double, scale: CGFloat, offsetY: CGFloat) -> NSImage {
        guard let glyph = symbol(name, pointSize: 13, color: color) else { return NSImage(size: size) }
        let image = NSImage(size: size, flipped: false) { rect in
            let w = glyph.size.width * scale, h = glyph.size.height * scale
            NSGraphicsContext.current?.saveGraphicsState()
            // Rotate around the bottom edge – like a wrist.
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY - h / 2 + offsetY)
            transform.rotate(byDegrees: rotation)
            transform.concat()
            glyph.draw(in: NSRect(x: -w / 2, y: 0, width: w, height: h))
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }
}
