import SwiftUI

/// Onglet Notifications : les dernières notifications reçues, plus récentes d'abord.
struct NotificationHistoryView: View {
    @Environment(AlertCenter.self) private var alerts

    var body: some View {
        Group {
            if alerts.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 22))
                    Text("Aucune notification pour l'instant")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(alerts.history) { alert in
                            HistoryRow(alert: alert)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { alerts.markAllRead() }
        .onChange(of: alerts.unreadCount) { alerts.markAllRead() }
    }
}

private struct HistoryRow: View {
    @Environment(AlertCenter.self) private var alerts
    let alert: NotchAlert
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AlertIcon(icon: alert.icon)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(alert.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text([alert.source, alert.body].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.1 : 0.05))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { alerts.perform(alert) }
        .contextMenu {
            Button("Retirer") { withAnimation(.snappy) { alerts.removeFromHistory(alert) } }
        }
    }
}
