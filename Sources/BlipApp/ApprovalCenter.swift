import AppKit
import UserNotifications
import BlipShared

/// An open permission request from a Copilot CLI session.
struct PermissionRequest: Identifiable, Equatable {
    let id: String            // Copilot's requestId
    let sessionId: String
    let project: String
    let kind: String          // shell, write, read, url, mcp, custom-tool, memory …
    let summary: String       // command, file name, URL …
    let intention: String?    // "Run the test suite"
    let sessionLabel: String? // what "For session" covers, e.g. "npm" – nil = not offered
    let hostApp: String?
    let createdAt: Date

    var label: String { Self.label(for: kind) }

    var symbol: String {
        switch kind {
        case "shell": "terminal.fill"
        case "write": "pencil"
        case "read": "doc.text"
        case "url": "globe"
        case "mcp": "puzzlepiece.extension.fill"
        case "memory": "brain"
        default: "hand.raised.fill"
        }
    }

    static func label(for kind: String?) -> String {
        switch kind {
        case "shell": "Run command"
        case "write": "Write file"
        case "read": "Read file"
        case "url": "Fetch URL"
        case "mcp": "Use MCP tool"
        case "custom-tool": "Use tool"
        case "memory": "Store memory"
        default: "Permission"
        }
    }
}

enum ApprovalDecision: String {
    case once = "approve-once"
    case session = "approve-for-session"
    case reject = "reject"
}

/// Approvals from the menu bar.
///
/// The Copilot CLI extension reports every permission request right away. Copilot shows it in the terminal
/// at the same time – whoever answers first wins. Answer in the terminal and "permissionDone" removes the card.
@MainActor
final class ApprovalCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var pending: [PermissionRequest] = []

    /// Clicking the notification itself → open the popover.
    var onOpenPopover: (() -> Void)?
    /// Send the answer to the session's extension.
    var sendToSession: ((String, [String: Any]) -> Bool)?

    private let store: SessionStore
    private var notificationsAvailable = false

    private static let categoryId = "BLIP_PERMISSION"
    private static let allowAction = "ALLOW"
    private static let denyAction = "DENY"

    init(store: SessionStore) {
        self.store = store
        super.init()
    }

    func start() {
        setUpNotifications()
    }

    // MARK: Messages from the extension

    func requested(_ sessionId: String, _ msg: [String: Any]) {
        guard let id = msg["requestId"] as? String, !pending.contains(where: { $0.id == id }) else { return }
        let session = store.sessions[sessionId]
        let request = PermissionRequest(
            id: id,
            sessionId: sessionId,
            project: session?.project ?? "Copilot",
            kind: msg["kind"] as? String ?? "unknown",
            summary: msg["summary"] as? String ?? "",
            intention: msg["intention"] as? String,
            sessionLabel: msg["sessionLabel"] as? String,
            hostApp: session?.hostApp,
            createdAt: Date()
        )
        pending.append(request)
        BlipLog.write("app", "Permission requested: \(request.label) – \(request.summary.prefix(120))")
        postNotification(for: request)
    }

    /// Answered – via Blip or in the terminal.
    func completed(_ requestId: String, result: String?) {
        guard pending.contains(where: { $0.id == requestId }) else { return }
        pending.removeAll { $0.id == requestId }
        removeNotification(requestId)
        BlipLog.write("app", "Permission answered: \(result ?? "?")")
    }

    func sessionGone(_ sessionId: String) {
        for request in pending where request.sessionId == sessionId {
            completed(request.id, result: "session ended")
        }
    }

    // MARK: Your decision

    func decide(_ request: PermissionRequest, _ decision: ApprovalDecision) {
        var message: [String: Any] = ["type": "decide", "requestId": request.id, "decision": decision.rawValue]
        if decision == .reject { message["feedback"] = "The user denied this via Blip." }
        let sent = sendToSession?(request.sessionId, message) ?? false
        BlipLog.write("app", "Decision \(decision.rawValue) for \(request.summary.prefix(80)) – \(sent ? "sent" : "session unreachable")")
        // The card disappears right away; Copilot confirms shortly after with permissionDone.
        pending.removeAll { $0.id == request.id }
        removeNotification(request.id)
    }

    // MARK: Notifications with "Allow" / "Deny"

    private func setUpNotifications() {
        // No notifications without an app bundle (e.g. `make dev`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allowAction, title: "Allow", options: [])
        let deny = UNNotificationAction(identifier: Self.denyAction, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryId, actions: [allow, deny], intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { BlipLog.write("app", "Notifications unavailable: \(error.localizedDescription)") }
            Task { @MainActor in self?.notificationsAvailable = granted }
        }
    }

    private func postNotification(for request: PermissionRequest) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(request.project): \(request.label)"
        content.body = request.summary
        if let intention = request.intention { content.subtitle = intention }
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.id, content: content, trigger: nil))
    }

    private func removeNotification(_ id: String) {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        Task { @MainActor in
            if let request = self.pending.first(where: { $0.id == id }) {
                switch action {
                case Self.allowAction: self.decide(request, .once)
                case Self.denyAction: self.decide(request, .reject)
                default: self.onOpenPopover?()
                }
            }
            completionHandler()
        }
    }
}
