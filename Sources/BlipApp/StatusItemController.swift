import AppKit
import SwiftUI
import Combine
import BlipShared

/// The menu bar icon (like Bluetooth, Wi-Fi …) plus the popover with all sessions.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: SessionStore
    private let approvals: ApprovalCenter
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    private var animationTimer: Timer?
    private let appStart = Date()
    private var shownState: SessionState = .idle
    private var stateChangedAt = Date.distantPast

    init(store: SessionStore, approvals: ApprovalCenter) {
        self.store = store
        self.approvals = approvals
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BlipStatusItem"
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
            button.toolTip = "Blip"
        }
        statusItem = item

        let content = PopoverView(
            store: store,
            approvals: approvals,
            onJump: { [weak self] session in self?.jump(to: session) },
            onQuit: { NSApp.terminate(nil) }
        )
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // objectWillChange fires *before* the change → redraw on the next run loop pass.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        approvals.onOpenPopover = { [weak self] in self?.showPopover() }

        refresh()
    }

    // MARK: Icon

    private func refresh() {
        let state = store.aggregate
        if state != shownState {
            shownState = state
            stateChangedAt = Date()
        }
        redraw()

        let needsTimer = MenuBarIcon.isAnimated(state, sinceChange: Date().timeIntervalSince(stateChangedAt))
        if needsTimer, animationTimer == nil {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(animationTimer!, forMode: .common) // keeps running while menus are open
        } else if !needsTimer {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func tick() {
        redraw()
        if !MenuBarIcon.isAnimated(shownState, sinceChange: Date().timeIntervalSince(stateChangedAt)) {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func redraw() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        button.image = MenuBarIcon.image(
            for: shownState,
            t: now.timeIntervalSince(appStart),
            sinceChange: now.timeIntervalSince(stateChangedAt)
        )

        // Several sessions in the same state → show the count next to it.
        let count = store.aggregateCount
        let title = (shownState != .idle && count > 1) ? "\(count)" : ""
        if button.title != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .baselineOffset: 0.5,
            ])
        }
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        let sessions = store.ordered
        guard !sessions.isEmpty else { return "Blip – no active sessions" }
        return sessions.prefix(5).map { "\($0.project): \($0.detail)" }.joined(separator: "\n")
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate()
        popover.animates = true  // fade in gently …
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        // … but resize (expanding a session) without the popover's own animation –
        // otherwise two animations overlap and the content flickers.
        popover.animates = false
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        popover.animates = true  // fade out gently
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        // Whoever saw the list has also seen "Done".
        store.acknowledgeFinished()
    }

    // MARK: Jump to session

    private static let editorBundlePrefixes = ["com.microsoft.VSCode", "com.vscodium"]

    private func jump(to session: Session) {
        store.acknowledge(session.id)
        popover.performClose(nil)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        guard let hostPath = session.hostApp else {
            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
            }
            return
        }
        let appURL = URL(fileURLWithPath: hostPath)
        let bundleId = Bundle(url: appURL)?.bundleIdentifier ?? ""

        // Terminal / iTerm: bring exactly the tab with the session's TTY to the front.
        if let tty = session.tty, let script = TerminalFocus.script(bundleId: bundleId, tty: tty) {
            if TerminalFocus.run(script) { return }
        }

        if Self.editorBundlePrefixes.contains(where: { bundleId.hasPrefix($0) }),
           let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
            // VS Code: open the project folder → focuses the right window.
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: config)
        } else {
            // Other terminals: at least bring the app to the front.
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }
}

/// Uses AppleScript to bring a session's exact terminal window/tab to the front.
/// The first time, macOS asks whether Blip may control the terminal.
enum TerminalFocus {
    static func script(bundleId: String, tty: String) -> String? {
        let tty = tty.replacingOccurrences(of: "\"", with: "")
        switch bundleId {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            if miniaturized of w then set miniaturized of w to false
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "notfound"
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "notfound"
            """
        default:
            return nil
        }
    }

    /// true = window found and brought to the front
    @MainActor
    static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            BlipLog.write("app", "Jump to session failed: \(error[NSAppleScript.errorMessage] ?? error)")
            return false
        }
        return result?.stringValue == "ok"
    }
}
