import Testing

@testable import Encoche

@MainActor
struct MeetingControllerTests {
    @Test func matchesMeetCameraButtonWithShortcutSuffix() {
        #expect(MeetingController.matchesMeetButton("Désactiver la caméra (⌘ + E)", labels: MeetingController.meetCameraLabels))
        #expect(MeetingController.matchesMeetButton("Turn on camera (ctrl + e)", labels: MeetingController.meetCameraLabels))
    }

    @Test func matchesMeetLeaveButtonWithCurlyApostrophe() {
        #expect(MeetingController.matchesMeetButton("Quitter l’appel", labels: MeetingController.meetLeaveLabels))
        #expect(MeetingController.matchesMeetButton("Leave call", labels: MeetingController.meetLeaveLabels))
    }

    @Test func ignoresUnrelatedButtons() {
        #expect(!MeetingController.matchesMeetButton("Désactiver le micro", labels: MeetingController.meetCameraLabels))
        #expect(!MeetingController.matchesMeetButton("", labels: MeetingController.meetLeaveLabels))
    }
}
