import Foundation
import Combine
import BlipShared

enum SessionState: String, Codable {
    case idle, working, needsInput, done, error

    /// What the menu bar icon shows when several sessions are running.
    var priority: Int {
        switch self {
        case .needsInput: 4
        case .error: 3
        case .working: 2
        case .done: 1
        case .idle: 0
        }
    }
}

/// One entry in a session's live feed.
struct Activity: Identifiable, Equatable {
    enum Kind: Equatable { case user, tool, assistant, permission, error }

    let id = UUID()
    var kind: Kind
    var text: String
    /// e.g. the shell command or file path
    var detail: String?
    /// last output lines of a command
    var output: String?
    var toolCallId: String?
    var requestId: String?
    /// nil = still running, true/false = result (tool succeeded / permission granted)
    var success: Bool?
    var at = Date()
}

struct Session: Identifiable, Equatable {
    let id: String
    var cwd: String?
    var hostApp: String?
    /// terminal device, e.g. /dev/ttys003 – to jump to the exact tab
    var tty: String?
    var title: String?
    var state: SessionState = .idle
    /// what's running right now, e.g. "Running command · npm test"
    var tool: String?
    var message: String?
    var stateSince = Date()
    var lastEvent = Date()
    /// "Done" or "Error" has been seen → stop showing it in the menu bar icon.
    var acknowledged = false
    /// live feed
    var activity: [Activity] = []

    var project: String {
        guard let cwd, !cwd.isEmpty else { return "Copilot" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Does this session count for the menu bar icon?
    var isAttention: Bool {
        switch state {
        case .idle: false
        case .done, .error: !acknowledged
        case .working, .needsInput: true
        }
    }

    var detail: String {
        switch state {
        case .idle: "Ready"
        case .working: tool.map { "Working · \($0)" } ?? "Thinking …"
        case .needsInput: message ?? "Needs your input"
        case .done: lastAnswer.map { "Done: \($0)" } ?? "Done"
        case .error: message ?? "Error"
        }
    }

    private var lastAnswer: String? {
        activity.last { $0.kind == .assistant }.map { $0.text.replacingOccurrences(of: "\n", with: " ") }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [String: Session] = [:]

    private static let maxActivity = 40

    // MARK: Derived values

    var ordered: [Session] {
        sessions.values.sorted {
            $0.state.priority != $1.state.priority ? $0.state.priority > $1.state.priority : $0.lastEvent > $1.lastEvent
        }
    }

    /// State of the menu bar icon.
    var aggregate: SessionState {
        sessions.values.filter(\.isAttention).max { $0.state.priority < $1.state.priority }?.state ?? .idle
    }

    var aggregateCount: Int {
        let agg = aggregate
        return sessions.values.filter { $0.isAttention && $0.state == agg }.count
    }

    // MARK: Copilot CLI extension

    func applyExtension(_ sessionId: String, _ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        if type == "bye" {
            sessions[sessionId] = nil
            persist()
            return
        }
        var s = sessions[sessionId] ?? Session(id: sessionId)
        s.lastEvent = Date()

        switch type {
        case "hello":
            s.cwd = msg["cwd"] as? String ?? s.cwd
            s.hostApp = msg["hostApp"] as? String ?? s.hostApp
            s.tty = msg["tty"] as? String ?? s.tty
            s.title = msg["title"] as? String ?? s.title

        case "title":
            s.title = msg["title"] as? String ?? s.title

        case "activity":
            applyActivity(&s, msg)

        case "permission":
            let summary = msg["summary"] as? String ?? "Permission"
            append(&s, Activity(kind: .permission, text: PermissionRequest.label(for: msg["kind"] as? String),
                                detail: summary, requestId: msg["requestId"] as? String))
            s.message = "Waiting for your approval"
            set(&s, .needsInput)

        case "permissionDone":
            let requestId = msg["requestId"] as? String
            let approved = (msg["result"] as? String).map { $0.hasPrefix("approved") } ?? false
            if let index = s.activity.lastIndex(where: { $0.requestId != nil && $0.requestId == requestId }) {
                s.activity[index].success = approved
            }
            if s.state == .needsInput && !s.activity.contains(where: { $0.kind == .permission && $0.success == nil }) {
                s.message = nil
                set(&s, .working)
            }

        default:
            break
        }
        sessions[sessionId] = s
        persist()
    }

    private func applyActivity(_ s: inout Session, _ msg: [String: Any]) {
        let kind = msg["kind"] as? String ?? ""
        let text = msg["text"] as? String
        switch kind {
        case "user":
            if let text { append(&s, Activity(kind: .user, text: text)) }
            s.tool = nil
            s.message = nil
            set(&s, .working)

        case "working":
            if s.state != .needsInput { set(&s, .working) }

        case "toolStart":
            let title = msg["title"] as? String ?? msg["tool"] as? String ?? "Tool"
            let detail = msg["detail"] as? String
            s.tool = detail.map { "\(title) · \($0)" } ?? title
            append(&s, Activity(kind: .tool, text: msg["intention"] as? String ?? title, detail: detail,
                                toolCallId: msg["toolCallId"] as? String))
            if s.state != .needsInput { set(&s, .working) }

        case "toolOutput":
            if let id = msg["toolCallId"] as? String,
               let index = s.activity.lastIndex(where: { $0.toolCallId == id }) {
                s.activity[index].output = text
            }

        case "toolEnd":
            if let id = msg["toolCallId"] as? String,
               let index = s.activity.lastIndex(where: { $0.toolCallId == id }) {
                s.activity[index].success = msg["success"] as? Bool ?? true
            }

        case "assistant":
            if let text { append(&s, Activity(kind: .assistant, text: text)) }

        case "idle":
            s.tool = nil
            if s.state != .error { set(&s, .done) }

        case "error":
            s.message = text
            if let text { append(&s, Activity(kind: .error, text: text)) }
            set(&s, .error)

        default:
            break
        }
    }

    /// A session's extension went away without saying bye (e.g. terminal window closed).
    func extensionDisconnected(_ sessionId: String) {
        guard sessions[sessionId] != nil else { return }
        sessions[sessionId] = nil
        persist()
    }

    // MARK: Helpers

    private func set(_ s: inout Session, _ state: SessionState) {
        guard s.state != state else { return }
        s.state = state
        s.stateSince = Date()
        s.acknowledged = false
    }

    private func append(_ s: inout Session, _ item: Activity) {
        s.activity.append(item)
        if s.activity.count > Self.maxActivity { s.activity.removeFirst(s.activity.count - Self.maxActivity) }
    }

    /// After the list was opened: finished sessions count as seen.
    func acknowledgeFinished() {
        for (id, s) in sessions where (s.state == .done || s.state == .error) && !s.acknowledged {
            sessions[id]?.acknowledged = true
        }
    }

    func acknowledge(_ id: String) {
        sessions[id]?.acknowledged = true
    }

    func clearFinished() {
        sessions = sessions.filter { $0.value.state != .done && $0.value.state != .error && $0.value.state != .idle }
        persist()
    }

    /// Writes the state for `blip status`.
    private func persist() {
        let snapshots = ordered.map {
            SessionSnapshot(id: $0.id, project: $0.project, state: $0.state.rawValue,
                            detail: $0.detail, since: $0.stateSince.timeIntervalSince1970)
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: BlipPaths.stateFile, options: .atomic)
        }
    }
}
