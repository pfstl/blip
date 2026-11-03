import AppKit
import SwiftUI

/// Draws Blip – a little ghost – in the menu bar, for a state at animation time `t` (seconds).
///
/// Like Bluetooth & co., "idle" and "working" are monochrome template images
/// (macOS tints them for light/dark). Blip only turns colorful when you need to act
/// or something happened.
///
/// All coordinates are in a 20 × 18 pt canvas with the origin at the top left (like SVG).
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 18)

    /// - Parameters:
    ///   - t: seconds since app launch (for looping animations)
    ///   - sinceChange: seconds since the last state change (for pop/shake effects)
    static func image(for state: SessionState, t: Double, sinceChange: Double) -> NSImage {
        switch state {
        case .idle: return sleeping()
        case .working: return working(t: t)
        case .needsInput: return waving(t: t, sinceChange: sinceChange)
        case .done: return happy(sinceChange: sinceChange)
        case .error: return dizzy(sinceChange: sinceChange)
        }
    }

    /// Is an animation running (timer needed)?
    static func isAnimated(_ state: SessionState, sinceChange: Double) -> Bool {
        switch state {
        case .working, .needsInput: true
        case .done: sinceChange < 1.2
        case .error: sinceChange < 1.0
        case .idle: false
        }
    }

    // MARK: - States

    /// Idle: Blip sleeps – closed eyes and a little "z".
    private static func sleeping() -> NSImage {
        render(template: true) {
            drawGhost(color: .black, eyes: .sleepy)
            NSColor.black.withAlphaComponent(0.55).setStroke()
            let z = NSBezierPath()
            z.move(to: CGPoint(x: 15, y: 2.5))
            z.line(to: CGPoint(x: 18, y: 2.5))
            z.line(to: CGPoint(x: 15, y: 5.7))
            z.line(to: CGPoint(x: 18, y: 5.7))
            z.lineWidth = 1.2
            z.lineCapStyle = .round
            z.lineJoinStyle = .round
            z.stroke()
        }
    }

    /// Working: Blip floats up and down, looks around and leaves a pulsing trail.
    private static func working(t: Double) -> NSImage {
        let bob = -1.6 * (1 - cos(2 * .pi * t / 1.1)) / 2
        let look = keyframes(t.truncatingRemainder(dividingBy: 3.4) / 3.4,
                             [(0, 0), (0.2, 0), (0.3, 1.1), (0.55, 1.1), (0.65, -0.9), (0.85, -0.9), (1, 0)])
        return render(template: true) {
            drawGhost(color: .black, eyes: .open(lookX: look), offsetY: bob)
            let trail: [(x: CGFloat, y: CGFloat, r: CGFloat, delay: Double)] =
                [(15.6, 13.6, 0.9, 0), (17.4, 11.6, 0.75, 0.15), (18.8, 9.4, 0.6, 0.3)]
            for dot in trail {
                let pulse = (1 - cos(2 * .pi * (t - dot.delay) / 1.1)) / 2
                NSColor.black.withAlphaComponent(0.2 + 0.6 * pulse).setFill()
                circle(dot.x, dot.y, dot.r).fill()
            }
        }
    }

    /// Needs you: orange Blip with big eyes hops and waves (right after the change, then every 3.2 s).
    private static func waving(t: Double, sinceChange: Double) -> NSImage {
        let phase = sinceChange < 1.6
            ? sinceChange.truncatingRemainder(dividingBy: 0.8) // right after the change: wave twice
            : t.truncatingRemainder(dividingBy: 3.2)           // then once every 3.2 s
        let angle = phase < 0.8 ? sin(phase / 0.8 * .pi * 4) * 20 : 0
        let hop = phase < 0.4 ? -sin(phase / 0.4 * .pi) * 2 : 0
        let color = NSColor(Theme.waiting)
        return render(template: false) {
            drawGhost(color: color, eyes: .alert, offsetY: hop) {
                // The arm sits behind the body and swings around the shoulder.
                withTransform(rotateDegrees: angle, around: CGPoint(x: 13.4, y: 10.8)) {
                    color.setStroke()
                    color.setFill()
                    let arm = NSBezierPath()
                    arm.move(to: CGPoint(x: 13.4, y: 10.8))
                    arm.line(to: CGPoint(x: 16.6, y: 7.2))
                    arm.lineWidth = 1.8
                    arm.lineCapStyle = .round
                    arm.stroke()
                    circle(17, 6.6, 1.5).fill()
                }
            }
        }
    }

    /// Done: green Blip with happy eyes pops in, a sparkle follows.
    private static func happy(sinceChange: Double) -> NSImage {
        let color = NSColor(Theme.done)
        let pop = overshoot(sinceChange, damping: 7, frequency: 13)
        let s = max(0, sinceChange - 0.15) // the sparkle comes a moment later
        let sparkle = overshoot(s, damping: 8, frequency: 14)
        let spin = min(s / 0.5, 1) * 90
        return render(template: false) {
            drawGhost(color: color, eyes: .happy, scale: pop)
            if sparkle > 0.01 {
                withTransform(rotateDegrees: spin, scale: sparkle, around: CGPoint(x: 16.5, y: 4.5)) {
                    color.setFill()
                    let star = NSBezierPath()
                    star.move(to: CGPoint(x: 16.5, y: 1.6))
                    quad(star, to: CGPoint(x: 19.4, y: 4.5), control: CGPoint(x: 16.9, y: 4.1))
                    quad(star, to: CGPoint(x: 16.5, y: 7.4), control: CGPoint(x: 16.9, y: 4.9))
                    quad(star, to: CGPoint(x: 13.6, y: 4.5), control: CGPoint(x: 16.1, y: 4.9))
                    quad(star, to: CGPoint(x: 16.5, y: 1.6), control: CGPoint(x: 16.1, y: 4.1))
                    star.close()
                    star.fill()
                }
            }
        }
    }

    /// Error: red Blip with x-eyes shakes its head once.
    private static func dizzy(sinceChange: Double) -> NSImage {
        let e = min(sinceChange, 1)
        let rotation = e >= 1 ? 0 : sin(e * .pi * 8) * 12 * (1 - e)
        return render(template: false) {
            drawGhost(color: NSColor(Theme.error), eyes: .x, rotation: rotation)
        }
    }

    // MARK: - The ghost

    private enum Eyes {
        case sleepy, open(lookX: CGFloat), alert, happy, x
    }

    /// Draws the ghost's body with its eyes punched out (so the menu bar shows through).
    /// `behind` is drawn first, inside the same transform – e.g. the waving arm.
    private static func drawGhost(color: NSColor, eyes: Eyes, offsetY: CGFloat = 0,
                                  scale: CGFloat = 1, rotation: Double = 0,
                                  behind: (() -> Void)? = nil) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        // Own transparency layer: punching out the eyes must only affect the ghost,
        // never whatever is drawn behind the icon.
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: offsetY)
        // Scale and rotate around the bottom center, like the ghost is standing there.
        transform.translateX(by: 8, yBy: 15.5)
        transform.rotate(byDegrees: rotation)
        transform.scale(by: scale)
        transform.translateX(by: -8, yBy: -15.5)
        transform.concat()

        behind?()
        color.setFill()
        body().fill()

        context.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSColor.black.setStroke()
        switch eyes {
        case .sleepy:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 4.6, y: 10.4))
            quad(path, to: CGPoint(x: 7, y: 10.4), control: CGPoint(x: 5.8, y: 11.6))
            path.move(to: CGPoint(x: 9, y: 10.4))
            quad(path, to: CGPoint(x: 11.4, y: 10.4), control: CGPoint(x: 10.2, y: 11.6))
            strokeRound(path, width: 1.3)
        case .open(let lookX):
            circle(6.1 + lookX, 9.9, 1.2).fill()
            circle(10.1 + lookX, 9.9, 1.2).fill()
        case .alert:
            circle(5.9, 9.5, 1.4).fill()
            circle(10.1, 9.5, 1.4).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 11.7, width: 1.6, height: 2)).fill()
        case .happy:
            let path = NSBezierPath()
            for x: CGFloat in [4.8, 8.8] {
                path.move(to: CGPoint(x: x, y: 10.7))
                path.line(to: CGPoint(x: x + 1.2, y: 9.3))
                path.line(to: CGPoint(x: x + 2.4, y: 10.7))
            }
            strokeRound(path, width: 1.3)
        case .x:
            let path = NSBezierPath()
            for x: CGFloat in [5, 9] {
                path.move(to: CGPoint(x: x, y: 8.7))
                path.line(to: CGPoint(x: x + 2, y: 10.7))
                path.move(to: CGPoint(x: x + 2, y: 8.7))
                path.line(to: CGPoint(x: x, y: 10.7))
            }
            strokeRound(path, width: 1.2)
        }
        context.compositingOperation = .sourceOver
        context.cgContext.endTransparencyLayer()
        context.restoreGraphicsState()
    }

    /// Dome on top, wavy hem at the bottom.
    private static func body() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 2, y: 15.5))
        path.line(to: CGPoint(x: 2, y: 10))
        path.appendArc(withCenter: CGPoint(x: 8, y: 10), radius: 6, startAngle: 180, endAngle: 360, clockwise: false)
        path.line(to: CGPoint(x: 14, y: 15.5))
        var x: CGFloat = 14
        for i in 0..<4 {
            let dip: CGFloat = i.isMultiple(of: 2) ? -1.3 : 1.3
            quad(path, to: CGPoint(x: x - 3, y: 15.5), control: CGPoint(x: x - 1.5, y: 15.5 + dip))
            x -= 3
        }
        path.close()
        return path
    }

    // MARK: - Helpers

    /// Renders into a fresh image with a top-left origin.
    private static func render(template: Bool, _ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            draw()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Blip"
        return image
    }

    private static func withTransform(rotateDegrees: Double, scale: CGFloat = 1, around center: CGPoint, _ draw: () -> Void) {
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: rotateDegrees)
        transform.scale(by: scale)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()
        draw()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private static func strokeRound(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// Quadratic curve as a cubic one (works on every macOS version).
    private static func quad(_ path: NSBezierPath, to end: CGPoint, control: CGPoint) {
        let start = path.currentPoint
        path.curve(to: end,
                   controlPoint1: CGPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y)),
                   controlPoint2: CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y)))
    }

    /// Springy 0 → 1 with a little overshoot, settled after one second.
    private static func overshoot(_ time: Double, damping: Double, frequency: Double) -> CGFloat {
        let e = min(max(time, 0), 1)
        if e >= 1 { return 1 }
        return CGFloat(max(0, 1 - exp(-damping * e) * cos(frequency * e)))
    }

    /// Eased interpolation between (progress, value) keyframes; progress runs from 0 to 1.
    private static func keyframes(_ progress: Double, _ frames: [(Double, Double)]) -> CGFloat {
        for (a, b) in zip(frames, frames.dropFirst()) where progress <= b.0 {
            let local = b.0 > a.0 ? (progress - a.0) / (b.0 - a.0) : 1
            let eased = local * local * (3 - 2 * local)
            return CGFloat(a.1 + (b.1 - a.1) * eased)
        }
        return CGFloat(frames.last?.1 ?? 0)
    }
}
