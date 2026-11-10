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
