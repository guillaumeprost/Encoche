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
