@testable import DistrictCall
import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The two call surfaces: the ring panel for an inbound call, and the in-call view a dialled
/// or answered call is drawn in.
///
/// ⛔ NO CALL IS CONNECTED HERE. A connected call needs a LiveKit room, which no snapshot
/// opens; the in-call view is a function of one ``LiveCallDisplay``, so it is drawn from a
/// softphone state set to each phase, as the call engine's events would leave it.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class CallScreenTests: ScreenSnapshotCase {
    /// The ring panel's content size (``RingPanelController``).
    private static let panelSize = CGSize(width: 380, height: 360)
    /// The Dial section's detail column, where a dialled call is drawn.
    private static let callSize = CGSize(width: 560, height: 620)

    /// The call in `district-call-detail.json`, which the ring looks its caller up from.
    private static let callId = "call_contract_answered"

    // MARK: - Incoming call

    func testIncomingCall() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("ringing", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.panelSize
            ) { app in
                Self.incoming(app, then: nil)
            }
        }
        // Declined: the summary and its Done.
        let declined = Self.writes(".*/decline", .fixture("mobile/district-call-decline.json")) + ScreenRules.loaded
        try await assertView("declined-en", rules: declined, size: Self.panelSize) { app in
            Self.incoming(app) { model in model.declinePressed() }
        }
    }

    /// The ring panel for the recorded call, rung by the gate as the telemetry would, and
    /// `then` run once it rings.
    private static func incoming(
        _ app: SignedInApp,
        then action: (@MainActor (IncomingCallModel) async -> Void)?
    ) -> AnyView {
        let model = IncomingCallModel(container: app.container, presenter: SilentRing())
        model.sessionChanged(.signedIn)
        model.ringStarted(workspaceId: app.workspaceId, callId: callId, workspaceName: "Zulu Agency")
        if let action {
            once({ model.isRinging }, { await action(model) })
        }
        return AnyView(IncomingCallView(model: model, devices: app.container.callStack.devices)
            .frame(minWidth: 340, minHeight: 320)
            .sheetPage().districtTheme())
    }

    /// The panel's ringer and notification, which a snapshot neither plays nor posts.
    private final class SilentRing: RingPresenting {
        func startRinging(workspaceId _: String, callId _: String) {}
        func stopRinging() {}
        func withdrawAlerts(callId _: String) {}
    }

    // MARK: - In call

    func testInCall() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("connected", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.callSize
            ) { app in
                Self.inCall(app) { state in
                    state.phase = .connected
                    state.media.elapsedSeconds = 65
                }
            }
        }
        // In the room, nobody on the line yet.
        try await assertView("ringing-en", rules: ScreenRules.loaded, size: Self.callSize) { app in
            Self.inCall(app) { state in state.phase = .ringing }
        }
        try await assertView("muted-en", rules: ScreenRules.loaded, size: Self.callSize) { app in
            Self.inCall(app) { state in
                state.phase = .connected
                state.media.elapsedSeconds = 65
                state.media.microphoneEnabled = false
            }
        }
        try await assertView("reconnecting-en", rules: ScreenRules.loaded, size: Self.callSize) { app in
            Self.inCall(app) { state in
                state.phase = .connected
                state.media.elapsedSeconds = 65
                state.media.reconnecting = true
            }
        }
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("ended", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.callSize
            ) { app in
                Self.inCall(app) { state in state.phase = .ended(.remoteHungUp) }
            }
        }
    }

    /// A dialled call to the recorded caller's number, in the phase `shape` leaves it in.
    private static func inCall(_ app: SignedInApp, shape: (inout SoftphoneState) -> Void) -> AnyView {
        var state = SoftphoneState(number: "+14165551234")
        shape(&state)
        return AnyView(InCallView(
            display: .softphone(state, endedByOperator: false),
            controls: InertControls(),
            devices: app.container.callStack.devices
        )
        .sheetPage().districtTheme())
    }

    /// Controls that do nothing: no button is pressed in a snapshot.
    @MainActor
    private final class InertControls: LiveCallControls {
        func toggleMute() {}
        func toggleSpeaker() async {}
        func hangUp() async {}
        func dismissEndedCall() {}
    }
}
