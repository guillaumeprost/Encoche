import SwiftUI
import UniformTypeIdentifiers

// MARK: - Onglet Étagère

struct ShelfView: View {
    @Environment(ShelfController.self) private var shelf
    @Environment(ScreenshotWatcher.self) private var screenshots

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                if shelf.items.isEmpty {
                    DropHintTile()
                } else {
                    ForEach(shelf.items, id: \.self) { url in
                        ShelfItem(url: url)
                    }
                }

                if !screenshots.screenshots.isEmpty {
                    SectionLabel(symbol: "camera.viewfinder", title: "Captures")
                    ForEach(screenshots.screenshots) { screenshot in
                        ScreenshotTile(screenshot: screenshot)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
    }
}

/// Étagère vide : explique comment y garder une capture.
private struct DropHintTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 20))
            Text("Clic droit sur une capture → Garder")
                .font(.system(size: 10.5))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(width: 104, height: 104)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.secondary.opacity(0.5))
        )
    }
}

/// Séparateur vertical entre les fichiers et les captures.
private struct SectionLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 8)
            VStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .frame(height: 104)
    }
}

/// Capture d'écran : miniature, à glisser vers une app ou à ouvrir.
private struct ScreenshotTile: View {
    @Environment(ShelfController.self) private var shelf
    @Environment(ScreenshotWatcher.self) private var screenshots
    let screenshot: ScreenshotWatcher.Screenshot
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumbnail = screenshots.thumbnails[screenshot.url] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(0.08))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12))
            )

            Text(screenshot.date, format: .relative(presentation: .named))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(4)
        .frame(width: 136, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: screenshot.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(screenshot.url) }
        .help(screenshot.url.lastPathComponent)
        .contextMenu {
            Button("Ouvrir") { shelf.open(screenshot.url) }
            Button("Afficher dans le Finder") { shelf.revealInFinder(screenshot.url) }
            Button("Envoyer par AirDrop") { shelf.airDrop([screenshot.url]) }
            Divider()
            Button("Garder sur l'étagère") { withAnimation(.snappy) { shelf.add([screenshot.url]) } }
        }
    }
}

private struct ShelfItem: View {
    @Environment(ShelfController.self) private var shelf
    let url: URL
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(8)
        .frame(width: 104, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.12 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        // Glisser vers une autre app (le fichier reste sur l'étagère).
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(url) }
        .help(url.path)
        .contextMenu {
            Button("Ouvrir") { shelf.open(url) }
            Button("Afficher dans le Finder") { shelf.revealInFinder(url) }
            Button("Envoyer par AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Retirer de l'étagère") {
                withAnimation(.snappy) { shelf.remove(url) }
            }
        }
    }
}
