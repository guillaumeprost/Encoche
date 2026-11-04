import SwiftUI
import UniformTypeIdentifiers

// MARK: - Zones de dépôt (pendant un glisser de fichier)

/// Affichées à la place du contenu quand un fichier est glissé sur l'encoche ouverte.
struct DropZonesView: View {
    @Environment(ShelfController.self) private var shelf
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            DropZone(symbol: "tray.and.arrow.down.fill", title: "Étagère", subtitle: "Garder sous la main") { urls in
                shelf.add(urls)
                settings.tab = .shelf
            }
            DropZone(symbol: "airplayaudio", title: "AirDrop", subtitle: "Envoyer à un appareil", tint: .blue) { urls in
                shelf.airDrop(urls)
            }
        }
    }
}

private struct DropZone: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isTargeted ? tint : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isTargeted ? 0.2 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? tint : .secondary.opacity(0.5))
        )
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            NSItemProvider.loadFileURLs(from: providers) { urls in
                if !urls.isEmpty { onDrop(urls) }
            }
            return true
        }
    }
}

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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            NSItemProvider.loadFileURLs(from: providers) { shelf.add($0) }
            return true
        }
    }
}

/// Étagère vide : rappelle qu'on peut y déposer des fichiers.
private struct DropHintTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20))
            Text("Glisse un fichier ici")
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
