import SwiftUI

/// Activités en direct sur l'écran verrouillé, en cartes empilées au-dessus du lecteur de
/// musique, comme sur iPhone : minuteur, Claude Code, prochaine réunion, téléchargement.
struct LockActivitiesView: View {
    @Environment(LockScreenController.self) private var lock
    @Environment(AppSettings.self) private var settings
    @Environment(TimerController.self) private var timer
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(CalendarController.self) private var calendar
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(MusicController.self) private var music

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if settings.lockScreenActivities {
                if timer.isActive { LockTimerCard() }
                if let session = claudeSession { LockClaudeCard(session: session) }
                if settings.showMeetingActivity, let meeting = calendar.upcomingMeeting { LockMeetingCard(meeting: meeting) }
                if settings.showDownloadActivity, downloads.showsActivity { LockDownloadCard() }
            }
            if settings.lockScreenMusic, music.track != nil {
                LockMusicCard()
                    .frame(height: LockScreenController.musicCardSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(lock.phase == .locked ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: lock.phase)
        .animation(.snappy, value: timer.isActive)
    }

    /// La session qui t'attend, sinon celle qui travaille.
    private var claudeSession: ClaudeCodeSession? {
        if let waiting = claudeCode.sortedSessions.first(where: { $0.state == .waiting }) { return waiting }
        return settings.showClaudeActivity ? claudeCode.workingSession : nil
    }
}

/// Fond commun des cartes : verre sombre arrondi.
private struct LockCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct LockTimerCard: View {
    @Environment(TimerController.self) private var timer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            let tint = timer.tint(remaining: remaining)
            let seconds = Int(remaining.rounded(.up))
            LockCard {
                HStack(spacing: 14) {
                    ZStack {
                        ProgressRing(fraction: timer.fraction(at: context.date), tint: tint, lineWidth: 4)
                        Image(systemName: timer.isPaused ? "pause.fill" : timer.kind.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.kind.label + (timer.isPaused ? " · en pause" : ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(Clock.text(seconds))
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .foregroundStyle(tint)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Spacer(minLength: 0)
                }
            }
            .animation(.linear(duration: 1), value: seconds)
        }
    }
}

private struct LockClaudeCard: View {
    let session: ClaudeCodeSession

    var body: some View {
        LockCard {
            HStack(spacing: 14) {
                ClaudeMascot(mood: session.state == .waiting ? .waiting : .working)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title ?? session.projectName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.state == .waiting ? (session.detail ?? "T'attend") : (session.detail ?? "Réfléchit…"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(session.state == .waiting ? Color.claude : .white.opacity(0.7))
                        .lineLimit(1)
                    if let fraction = session.planFraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(Color.claude)
                            .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LockMeetingCard: View {
    let meeting: CalendarEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LockCard {
                HStack(spacing: 14) {
                    Image(systemName: meeting.meetingURL != nil ? "video.fill" : "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(meeting.color)
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Dans \(MeetingCountdown.short(until: meeting.start, now: context.date)) · \(meeting.start.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(meeting.color)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct LockDownloadCard: View {
    @Environment(DownloadMonitor.self) private var downloads

    var body: some View {
        LockCard {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(fraction: downloads.fraction, tint: .blue, lineWidth: 4)
                    Image(systemName: downloads.finishedName != nil ? "checkmark" : "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(downloads.finishedName != nil ? .green : .blue)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(downloads.finishedName ?? downloads.currentName ?? "Téléchargement")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(downloads.finishedName != nil ? "Terminé" : downloads.fraction.map { "\(Int(($0 * 100).rounded())) %" } ?? "En cours…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.blue)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
