import SwiftUI

/// A session's live feed: your message, tool calls with output, approvals, answers.
struct ActivityFeed: View {
    let items: [Activity]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("Nothing here yet – the feed shows up as soon as the agent gets going.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    icon(for: item)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.text)
                            .font(.system(size: 11.5, weight: item.kind == .user ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(item.kind == .error ? Theme.error : .primary)
                            .lineLimit(item.kind == .assistant ? 4 : 2)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        if let output = item.output, !output.isEmpty {
                            Text(output)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.calm, value: items.map(\.id))
    }

    @ViewBuilder
    private func icon(for item: Activity) -> some View {
        switch item.kind {
        case .user:
            Image(systemName: "person.fill").foregroundStyle(.secondary)
        case .assistant:
            Image(systemName: "sparkles").foregroundStyle(Theme.working)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
        case .tool, .permission:
            switch item.success {
            case .none:
                if item.kind == .permission {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Theme.waiting)
                        .symbolEffect(.pulse)
                } else {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                }
            case .some(true):
                Image(systemName: "checkmark").foregroundStyle(Theme.done)
            case .some(false):
                Image(systemName: "xmark").foregroundStyle(Theme.error)
            }
        }
    }
}
