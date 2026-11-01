import AppKit
import BlipShared

/// The app has no windows – it lives only as an icon in the menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var store = SessionStore()
    private lazy var approvals = ApprovalCenter(store: store)
    private let extensionServer = ExtensionServer()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, even without a bundle (make dev)

        // Single instance only.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: BlipInfo.bundleId)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }

        try? FileManager.default.createDirectory(at: BlipPaths.base, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: BlipPaths.pidFile, atomically: true, encoding: .utf8)

        // Copilot CLI extension(s): live feed and approvals
        extensionServer.onMessage = { [weak self] sessionId, message in
            MainActor.assumeIsolated { self?.handleExtension(sessionId, message) }
        }
        extensionServer.onDisconnect = { [weak self] sessionId in
            MainActor.assumeIsolated {
                self?.store.extensionDisconnected(sessionId)
                self?.approvals.sessionGone(sessionId)
            }
        }
        do { try extensionServer.start() } catch { BlipLog.write("app", "Extension socket error: \(error)") }

        approvals.sendToSession = { [weak self] sessionId, message in
            self?.extensionServer.send(to: sessionId, message) ?? false
        }
        approvals.start()

        let statusItem = StatusItemController(store: store, approvals: approvals)
        statusItem.install()
        self.statusItem = statusItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        extensionServer.stop()
        try? FileManager.default.removeItem(at: BlipPaths.pidFile)
    }

    private func handleExtension(_ sessionId: String, _ message: [String: Any]) {
        let type = message["type"] as? String ?? "?"
        if type != "activity" || (message["kind"] as? String) != "toolOutput" {
            BlipLog.write("ext", "\(sessionId.prefix(8)) \(type) \(message["kind"] as? String ?? "")")
        }
        switch type {
        case "permission":
            store.applyExtension(sessionId, message)
            approvals.requested(sessionId, message)
        case "permissionDone":
            store.applyExtension(sessionId, message)
            approvals.completed(message["requestId"] as? String ?? "", result: message["result"] as? String)
        case "decideFailed":
            BlipLog.write("ext", "Answer not accepted: \(message["error"] as? String ?? "?")")
        case "bye":
            approvals.sessionGone(sessionId)
            store.applyExtension(sessionId, message)
        default:
            store.applyExtension(sessionId, message)
        }
    }
}
