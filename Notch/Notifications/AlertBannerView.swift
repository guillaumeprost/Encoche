import SwiftUI

/// Contenu de l'encoche quand une notification arrive : icône, titre, texte.
struct AlertBannerView: View {
    @Environment(AlertCenter.self) private var alerts
    let alert: NotchAlert

    private var hovered: Bool { alerts.isHovered }
    /// Un clic fait quelque chose (ouvre l'app, le lien…).
    private var isClickable: Bool { alert.action != nil && alert.buttons.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            content
            if !alert.buttons.isEmpty {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(alert.buttons) { button in
                        AlertButtonView(button: button) { alerts.press(button) }
                    }
                }
            }
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 11) {
            AlertIcon(icon: alert.icon)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if hovered && alert.buttons.isEmpty {
                        // Au survol : fermer sans ouvrir.
                        Button { alerts.dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(.primary.opacity(0.14)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Fermer")
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(alert.source)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.45))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                if let body = alert.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.75))
                        .lineLimit(hovered ? 5 : 2)
                        .fixedSize(horizontal: false, vertical: hovered)
                }
            }
            if hovered && isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.4))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(hovered && isClickable ? 0.08 : 0))
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: hovered)
        .onHover { inside in
            guard isClickable else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct AlertButtonView: View {
    let button: NotchAlert.Button
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(button.label)
                .font(.system(size: 11.5, weight: button.role == .primary ? .semibold : .medium))
                .foregroundStyle(button.role == .destructive ? Color.red : button.role == .primary ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if button.role == .primary {
                        Capsule().fill(Color.claude.opacity(hovering ? 1 : 0.85))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.primary.opacity(hovering ? 0.12 : 0.04)).interactive(), in: Capsule())
        .onHover { hovering = $0 }
    }
}

/// Icône d'une notification : celle de l'app, ou un symbole sur une pastille colorée.
struct AlertIcon: View {
    let icon: NotchAlert.Icon

    var body: some View {
        switch icon {
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                symbol("bell.fill", .gray)
            }
        case .symbol(let name, let color):
            symbol(name, color)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.gradient)
            .overlay {
                Image(systemName: name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
