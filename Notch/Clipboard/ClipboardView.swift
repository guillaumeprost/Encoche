import SwiftUI

/// Historique du presse-papier en cartes horizontales. Un clic recopie l'élément,
/// prêt à être collé avec ⌘V.
struct ClipboardView: View {
    @Environment(ClipboardController.self) private var clipboard
    @State private var copiedID: UUID?

    var body: some View {
        let items = clipboard.sortedItems
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 22))
                Text("Copie quelque chose, ça apparaîtra ici")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.primary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        ClipCard(item: item, isCopied: copiedID == item.id)
                            .onTapGesture { copy(item) }
                            .contextMenu {
                                Button("Copier") { copy(item) }
                                Button(item.pinned ? "Désépingler" : "Épingler") {
                                    withAnimation(.snappy) { clipboard.togglePin(item) }
                                }
                                Divider()
                                Button("Supprimer", role: .destructive) {
                                    withAnimation(.snappy) { clipboard.delete(item) }
                                }
                            }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
        }
    }

    private func copy(_ item: ClipItem) {
        withAnimation(.snappy) {
            clipboard.copy(item)
            copiedID = item.id
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == item.id { withAnimation { copiedID = nil } }
        }
    }
}

private struct ClipCard: View {
    @Environment(ClipboardController.self) private var clipboard
    let item: ClipItem
    let isCopied: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon = clipboard.appIcon(for: item.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(9)
        .frame(width: 150, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.14 : 0.08))
        )
        .overlay {
            if isCopied {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.55))
                    .overlay {
                        Label("Copié", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hovering ? 1.03 : 1)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11.5))
                .lineLimit(4)

        case .image:
            if let thumb = clipboard.thumbnail(for: item) {
                // Le cadre impose la taille et l'image le remplit en overlay : une image en
                // portrait ne peut plus agrandir la carte ni déborder de l'encoche.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo").foregroundStyle(.primary.opacity(0.5))
            }

        case .files(let urls):
            HStack(spacing: 8) {
                if let first = urls.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(urls.first?.lastPathComponent ?? "")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(2)
                    if urls.count > 1 {
                        Text("+ \(urls.count - 1) autre\(urls.count > 2 ? "s" : "")")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                }
            }
        }
    }
}
