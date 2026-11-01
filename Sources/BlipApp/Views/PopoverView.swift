import SwiftUI

/// Content of the popover below the menu bar icon.
struct PopoverView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var approvals: ApprovalCenter
    let onJump: (Session) -> Void
    let onQuit: () -> Void

    /// Expanded sessions (live feed visible)
    @State private var expanded: Set<String> = []
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let sessions = store.ordered
        VStack(alignment: .leading, spacing: 10) {
            header(sessions)

            if sessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse)
                    Text("No active Copilot sessions")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                // Always the same ScrollView – so expanding never rebuilds or re-animates anything.
                // It's exactly as tall as its content, but at most 460 pt.
                ScrollView(.vertical, showsIndicators: false) {
                    rows(sessions)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        })
                }
                .frame(height: min(max(contentHeight, 1), 460))
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            }

            Divider()

            HStack {
                Button("Clear Finished") { store.clearFinished() }
                    .disabled(!sessions.contains { $0.state == .done || $0.state == .error || $0.state == .idle })
                Spacer()
                Button("Quit Blip", action: onQuit)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 380)
        .animation(Theme.calm, value: sessions.map(\.id))
    }

    private func rows(_ sessions: [Session]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                SessionRow(
                    session: session,
                    index: index,
                    requests: approvals.pending.filter { $0.sessionId == session.id },
                    isExpanded: expanded.contains(session.id),
                    onToggle: {
                        withAnimation(Theme.calm) {
                            if expanded.contains(session.id) { expanded.remove(session.id) } else { expanded.insert(session.id) }
                        }
                    },
                    onJump: { onJump(session) },
                    onDecision: { request, decision in approvals.decide(request, decision) }
                )
                .transition(.opacity)
            }
        }
    }

    private func header(_ sessions: [Session]) -> some View {
        HStack(spacing: 6) {
            Text("Blip")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
            Spacer()
            ForEach([SessionState.needsInput, .working, .done], id: \.self) { state in
                let n = sessions.filter { $0.state == state }.count
                if n > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Theme.color(state)).frame(width: 7, height: 7)
                        Text("\(n)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
