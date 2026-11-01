import SwiftUI
import AppKit

struct SessionRow: View {
    static let height: CGFloat = 54

    let session: Session
    let index: Int
    /// Open permission requests of this session – shown right in the tile
    let requests: [PermissionRequest]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onJump: () -> Void
    let onDecision: (PermissionRequest, ApprovalDecision) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    StatusOrb(state: session.state, size: 12)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.project)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(session.detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.color(session.state).opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentTransition(.interpolate)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 4) {
                        ElapsedText(since: session.stateSince)
                        HostIcon(path: session.hostApp)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(session.activity.isEmpty ? 0 : 1)
                }
                .padding(.horizontal, 10)
                .frame(height: Self.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Array(requests.enumerated()), id: \.element.id) { i, request in
                ApprovalCard(request: request, isFirst: index == 0 && i == 0) { decision in
                    onDecision(request, decision)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = session.title {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ActivityFeed(items: Array(session.activity.suffix(8)))
                    Button(action: onJump) {
                        Label("Jump to Session", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering || isExpanded ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.color(session.state).opacity(session.state == .needsInput ? 0.55 : 0), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
        .animation(Theme.calm, value: session.state)
        .animation(Theme.calm, value: requests.map(\.id))
    }
}

/// Small icon of the app hosting the session (VS Code, Terminal, Copilot app …).
struct HostIcon: View {
    let path: String?
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let path, let image = Self.icon(for: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .opacity(0.85)
        }
    }

    private static func icon(for path: String) -> NSImage? {
        if let cached = cache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
