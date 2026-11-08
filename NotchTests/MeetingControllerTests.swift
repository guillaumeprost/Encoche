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

    @Test func cameraButtonShowsTheCameraState() {
        let on = MeetingController.cameraButton(isOn: true, app: "Meet")
        #expect(on.symbol == "video.fill")
        #expect(!on.isOff)
        #expect(on.help == "Couper la caméra (Meet)")
        let off = MeetingController.cameraButton(isOn: false, app: "Meet")
        #expect(off.symbol == "video.slash.fill")
        #expect(off.isOff)
        #expect(off.help == "Activer la caméra (Meet)")
    }
}
