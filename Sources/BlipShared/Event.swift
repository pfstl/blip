import Foundation

/// What `blip status` reads from the app.
public struct SessionSnapshot: Codable, Sendable {
    public var id: String
    public var project: String
    public var state: String
    public var detail: String
    public var since: Double

    public init(id: String, project: String, state: String, detail: String, since: Double) {
        self.id = id
        self.project = project
        self.state = state
        self.detail = detail
        self.since = since
    }
}

public extension String {
    func clipped(_ max: Int) -> String {
        count <= max ? self : String(prefix(max - 1)) + "…"
    }
}
