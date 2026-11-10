import Testing

@testable import Encoche

struct TrackChangeTests {
    private func track(_ title: String, by artist: String = "Daft Punk", album: String = "Discovery") -> MusicController.Track {
        MusicController.Track(title: title, artist: artist, album: album, duration: 200)
    }

    @Test func announcesANewSong() {
        #expect(MusicController.isNewSong(track("Aerodynamic"), after: track("One More Time")))
        #expect(MusicController.isNewSong(track("Intro", by: "The xx"), after: track("Intro")))
    }

    @Test func staysQuietOtherwise() {
        // Premier morceau connu (lancement de l'app, reprise après arrêt).
        #expect(!MusicController.isNewSong(track("One More Time"), after: nil))
        // Même titre : pause, reprise, album ou durée mis à jour.
        #expect(!MusicController.isNewSong(track("One More Time", album: "Alive"), after: track("One More Time")))
        // Titre vide pendant un chargement.
        #expect(!MusicController.isNewSong(track(""), after: track("One More Time")))
    }
}

struct MotionArtworkTests {
    @Test func findsTheSquareVideoInTheAlbumPage() {
        let page = """
            "videoArtwork":{"dictionary":{"motionDetailSquare":{"previewFrame":{"bgColor":"1f1c1c","width":3840},\
            "video":"https:\\u002F\\u002Fmvod.itunes.apple.com\\u002Fa\\u002FP1_default.m3u8"}}},\
            "tallVideoArtwork":{"dictionary":{"motionDetailTall":{"video":"https://mvod.itunes.apple.com/b/P2_default.m3u8"}}}
            """
        #expect(
            MusicExtras.motionArtworkURL(inAlbumPage: page)?.absoluteString == "https://mvod.itunes.apple.com/a/P1_default.m3u8")
    }

    @Test func noVideoWithoutMotionArtwork() {
        #expect(MusicExtras.motionArtworkURL(inAlbumPage: #"{"artwork":{"url":"https://is1-ssl.mzstatic.com/x.jpg"}}"#) == nil)
    }
}

struct ActivityTabTests {
    @Test func activitiesOpenTheirTab() {
        #expect(LiveActivity.music.tab == .music)
        #expect(LiveActivity.claudeWaiting.tab == .claude)
        #expect(LiveActivity.claudeWorking.tab == .claude)
        #expect(LiveActivity.meeting.tab == .calendar)
        #expect(LiveActivity.timer.tab == .home)
    }
}

@MainActor
struct KaraokeLayoutTests {
    @Test func karaokeAddsALineUnderTheActivity() {
        let vm = NotchViewModel()
        let activity = vm.shapeSize(showsActivity: true, tab: .home)
        vm.showsLiveLine = true
        let karaoke = vm.shapeSize(showsActivity: true, tab: .home)
        #expect(abs(karaoke.height - activity.height - NotchViewModel.liveLineHeight) < 0.01)
        #expect(karaoke.width > activity.width)
        // Une notification passe devant.
        vm.showsAlert = true
        #expect(vm.shapeSize(showsActivity: true, tab: .home).height != karaoke.height)
    }
}

struct KaraokeLyricsTests {
    @Test func sameSongIgnoresDurationAndAlbum() {
        let a = MusicController.Track(title: "Mentir au psy", artist: "BEN plg", album: "L'histoire sans fin", duration: 181)
        let b = MusicController.Track(title: "Mentir au psy", artist: "BEN plg", album: "Mentir au psy - Single", duration: 181.4)
        #expect(MusicExtras.sameSong(a, b))
        #expect(!MusicExtras.sameSong(a, MusicController.Track(title: "Paiement refusé", artist: "BEN plg", album: "", duration: 0)))
        #expect(!MusicExtras.sameSong(a, nil))
    }
}
