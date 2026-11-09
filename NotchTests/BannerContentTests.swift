import Testing

@testable import Encoche

/// Lecture du contenu des bannières de macOS.
struct BannerContentTests {
    @Test func readsAppTitleAndBody() {
        let content = BannerSuppressor.parse(
            description: "Messages, Léa, On se voit ce soir ?",
            texts: [(id: "title", value: "Léa"), (id: "body", value: "On se voit ce soir ?")])
        #expect(content == .init(app: "Messages", title: "Léa", body: "On se voit ce soir ?"))
    }

    @Test func summarizedNotificationsKeepTheAppName() {
        // Apple Intelligence préfixe l'app (avec une espace insécable avant les deux-points).
        let content = BannerSuppressor.parse(
            description: "Résumé\u{00A0}: Mail, Rose Barthe, Propose un rendez-vous jeudi",
            texts: [(id: "title", value: "Rose Barthe")])
        #expect(content.app == "Mail")
        #expect(content.title == "Rose Barthe")
        // Sans texte `body`, le résumé vient de la fin de la description.
        #expect(content.body == "Propose un rendez-vous jeudi")
        #expect(BannerSuppressor.parse(description: "Summary: Mail, A", texts: []).app == "Mail")
    }

    @Test func summaryTextWithoutIdentifierIsUsedAsBody() {
        let content = BannerSuppressor.parse(
            description: "Résumé : Mail, Rose Barthe",
            texts: [(id: "title", value: "Rose Barthe"), (id: nil, value: "2 messages : rendez-vous jeudi")])
        #expect(content.body == "2 messages : rendez-vous jeudi")
    }

    @Test func nothingReadableGivesNoTitle() {
        let content = BannerSuppressor.parse(description: "", texts: [])
        #expect(content == .init(app: "", title: nil, body: nil))
    }
}
