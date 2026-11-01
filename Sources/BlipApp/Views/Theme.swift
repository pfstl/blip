import SwiftUI

enum Theme {
    static let cyan = Color(red: 0.30, green: 0.85, blue: 1.00)
    static let blue = Color(red: 0.36, green: 0.55, blue: 1.00)
    static let violet = Color(red: 0.66, green: 0.45, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.45, blue: 0.75)

    static let working = Color(red: 0.40, green: 0.70, blue: 1.00)
    static let waiting = Color(red: 1.00, green: 0.72, blue: 0.22)
    static let done = Color(red: 0.33, green: 0.92, blue: 0.56)
    static let error = Color(red: 1.00, green: 0.38, blue: 0.43)
    static let idle = Color.secondary

    static let workingGradient = Gradient(colors: [cyan, blue, violet, pink, cyan])
    static let confetti: [Color] = [done, cyan, waiting, pink, violet, blue]

    static func color(_ state: SessionState) -> Color {
        switch state {
        case .idle: idle
        case .working: working
        case .needsInput: waiting
        case .done: done
        case .error: error
        }
    }

    static let springy = Animation.spring(response: 0.42, dampingFraction: 0.62)
    /// Calm animation for expanding/collapsing and layout changes in the popover
    static let calm = Animation.easeInOut(duration: 0.22)
    static let wobbly = Animation.spring(response: 0.5, dampingFraction: 0.5)
}
