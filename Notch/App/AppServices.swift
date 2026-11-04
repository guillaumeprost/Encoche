import SwiftUI

/// Services partagés par toutes les encoches (un seul exemplaire pour tous les écrans).
@MainActor
struct AppServices {
    let settings = AppSettings()
    let music = MusicController()
    let calendar = CalendarController()
    let clipboard = ClipboardController()
}

extension View {
    @MainActor
    func environment(_ services: AppServices) -> some View {
        environment(services.settings)
            .environment(services.music)
            .environment(services.calendar)
            .environment(services.clipboard)
    }
}
