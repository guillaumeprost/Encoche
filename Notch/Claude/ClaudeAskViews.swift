import SwiftUI

// MARK: - Question rapide

struct AskPanel: View {
    @Environment(ClaudeAsk.self) private var ask

    var body: some View {
        if ask.cliURL != nil {
            responseArea
                .contextMenu {
                    if !ask.askedQuestion.isEmpty {
                        Button("Nouvelle conversation") { ask.reset() }
                    }
                }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Claude Code introuvable", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Text("Installe la CLI Claude Code et connecte-toi pour poser des questions avec ton abonnement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var responseArea: some View {
        if let error = ask.errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                if ask.needsLogin {
                    Text("Dans un terminal, lance `claude` puis `/login`.")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if ask.askedQuestion.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.claude.opacity(0.7))
                Text("Pose une question à Claude dans le champ ci-dessous")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                Text("Entrée pour envoyer · Échap pour quitter le champ")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Échanges précédents de la conversation, en plus discret.
                        ForEach(ask.history) { exchange in
                            Text(exchange.question)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.4))
                                .lineLimit(1)
                            Text(claudeMarkdown(exchange.answer))
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.6))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 6)
                        }
                        Text(ask.askedQuestion)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.5))
                            .lineLimit(1)
                        if ask.answer.isEmpty && ask.isStreaming {
                            ThinkingDots()
                        } else {
                            Text(claudeMarkdown(ask.answer))
                                .font(.system(size: 13.5))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                .onChange(of: ask.answer) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .overlay(alignment: .topTrailing) {
                if !ask.history.isEmpty || !ask.answer.isEmpty {
                    Button {
                        ask.reset()
                    } label: {
                        Label("Nouvelle", systemImage: "square.and.pencil")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().fill(.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Nouvelle conversation")
                }
            }
        }
    }

}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.claude)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.6)))
                }
            }
            .padding(.vertical, 4)
        }
    }
}
