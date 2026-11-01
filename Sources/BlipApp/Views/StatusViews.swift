import SwiftUI

// All the small, playful state animations.
// Continuous motion runs through TimelineView (30 fps) – robust and cheap.

private let fps30 = 1.0 / 30

/// The colorful "orb" at the front of every session row.
struct StatusOrb: View {
    let state: SessionState
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            switch state {
            case .working: WorkingOrb(size: size)
            case .needsInput: WaitingOrb(size: size)
            case .done: DoneOrb(size: size)
            case .error: ErrorOrb(size: size)
            case .idle:
                Circle().fill(Theme.idle).frame(width: size * 0.5, height: size * 0.5)
            }
        }
        .frame(width: size * 2, height: size * 2)
        .id(state) // new state → new view → the entrance animation runs again
        .transition(.scale(scale: 0.2).combined(with: .opacity))
    }
}

/// Working: a rotating gradient that "breathes", with an orbiting highlight.
struct WorkingOrb: View {
    let size: CGFloat
    var body: some View {
        TimelineView(.animation(minimumInterval: fps30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(AngularGradient(gradient: Theme.workingGradient, center: .center))
                    .rotationEffect(.degrees(t * 260))
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: cos(t * 3.2) * size * 0.2, y: sin(t * 3.2) * size * 0.2)
                    .blur(radius: 0.6)
            }
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.1 * sin(t * 4.2))
        }
    }
}

/// Needs input: a bouncing amber dot with ripple rings.
struct WaitingOrb: View {
    let size: CGFloat
    var body: some View {
        TimelineView(.animation(minimumInterval: fps30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Theme.waiting, lineWidth: 1.5)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + phase * 1.1)
                        .opacity(1 - phase)
                }
                Circle()
                    .fill(Theme.waiting)
                    .frame(width: size, height: size)
                    .scaleEffect(1 + 0.14 * abs(sin(t * 5)))
                    .offset(y: -1.5 * abs(sin(t * 5)))
            }
        }
    }
}

/// Done: pops in with an overshoot, the checkmark bounces after.
struct DoneOrb: View {
    let size: CGFloat
    @State private var popped = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.done)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.58, weight: .black))
                .foregroundStyle(.black.opacity(0.75))
                .symbolEffect(.bounce, value: popped)
        }
        .frame(width: size, height: size)
        .scaleEffect(popped ? 1 : 0.1)
        .rotationEffect(.degrees(popped ? 0 : -90))
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.42)) { popped = true }
        }
    }
}

/// Error: a red dot that shakes its head when it appears.
struct ErrorOrb: View {
    let size: CGFloat
    @State private var shake = 0
    var body: some View {
        ZStack {
            Circle().fill(Theme.error)
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.6, weight: .black))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shake) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-4, duration: 0.07)
                CubicKeyframe(4, duration: 0.09)
                CubicKeyframe(-3, duration: 0.09)
                CubicKeyframe(2, duration: 0.09)
                SpringKeyframe(0, duration: 0.25)
            }
        }
        .onAppear { shake += 1 }
    }
}

/// "12s", "4m", "1h 3m"
struct ElapsedText: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(ctx.date.timeIntervalSince(since)))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
