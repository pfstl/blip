import AppKit

// Deliberately no SwiftUI `App`: its scenes (even an empty `Settings`) can open an empty
// window at launch. With plain AppKit there's only the menu bar icon.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
