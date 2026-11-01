import SwiftUI

/// An open permission request – shown right inside its session's tile.
struct ApprovalCard: View {
    let request: PermissionRequest
    /// Only the topmost card responds to ↩ (Allow).
    let isFirst: Bool
    let onDecision: (ApprovalDecision) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: request.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.waiting)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.waiting.opacity(0.18)))
                    .symbolEffect(.bounce, value: appeared)
                VStack(alignment: .leading, spacing: 1) {
                    Text(request.label)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let intention = request.intention {
                        Text(intention)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }

            if !request.summary.isEmpty {
                Text(request.summary)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            HStack(spacing: 6) {
                Button("Deny") { onDecision(.reject) }
                Spacer(minLength: 4)
                if let label = request.sessionLabel {
                    Button("For Session") { onDecision(.session) }
                        .help("Allow and don't ask again this session: \(label)")
                }
                allowButton
            }
            .controlSize(.small)

            Text("Copilot is asking in the terminal too – first answer wins.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.waiting.opacity(0.10)))
        .onAppear { appeared = true } // makes the icon bounce once
    }

    @ViewBuilder private var allowButton: some View {
        let button = Button("Allow") { onDecision(.once) }
            .buttonStyle(.borderedProminent)
            .tint(Theme.done.opacity(0.9))
        if isFirst {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}
