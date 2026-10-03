@testable import DistrictMac
import Foundation
import XCTest

/// ⛔ THE MAC'S CALL STACK WITHOUT CALLKIT: the call claim is the one-call-at-a-time rule and
/// the call model's lifetime, the Mac ends whatever is live for sleep, quit and sign-out, and
/// a quit waits (briefly) for a placed call's carrier hang-up.
@MainActor
final class MacCallStackTests: XCTestCase {
    private func stack() -> CallStack {
        CallStack(microphone: FakeMicrophoneAccess(status: .granted))
    }

    // MARK: - The claim

    func test_MAC_STACK_01_oneCallAtATime() {
        let calls = stack()
        let first = RecordingCallOwner()
        let second = RecordingCallOwner()

        XCTAssertTrue(calls.claimCall(first))
        XCTAssertTrue(calls.claimCall(first), "the owner may claim again")
        XCTAssertFalse(calls.claimCall(second), "a second call is refused while one is live")
        XCTAssertTrue(calls.hasLiveCall)

        calls.releaseCall(second)
        XCTAssertTrue(calls.callOwner === first, "only the owner can give the claim back")

        calls.releaseCall(first)
        XCTAssertFalse(calls.hasLiveCall)
        XCTAssertTrue(calls.claimCall(second))
    }

    func test_MAC_STACK_02_endingEverythingEndsTheCall() async {
        let calls = stack()
        let owner = RecordingCallOwner()
        calls.claimCall(owner)

        await calls.endEverything(.sleep)

        XCTAssertEqual(owner.systemEnds, 1)
    }

    // MARK: - The carrier hang-up that outlives the call

    func test_MAC_STACK_03_aQuitWaitsForAHangUpOnItsWay() async {
        let calls = stack()
        let sent = Counter()
        calls.trackServerHangUp {
            try? await Task.sleep(for: .milliseconds(100))
            sent.increment()
        }

        await calls.drainServerHangUps(within: 5)

        XCTAssertEqual(sent.value, 1, "the request finished before the drain returned")
    }

    func test_MAC_STACK_04_aQuitNeverHangsOnANetworkThatHasGone() async {
        let calls = stack()
        let gate = AsyncGate()
        calls.trackServerHangUp { await gate.wait() }
        let started = Date()

        await calls.drainServerHangUps(within: 0.2)

        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the drain is bounded")
        gate.open()
    }

    func test_MAC_STACK_05_nothingToDrainReturnsAtOnce() async {
        let started = Date()
        await stack().drainServerHangUps(within: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    // MARK: - The dialler under sleep, quit and sign-out

    /// ⛔ A PRESS STILL WAITING ON THE MICROPHONE QUESTION PLACES NOTHING when the Mac sleeps:
    /// the claim is given back, no sentence is left on the keypad, and the answer that arrives
    /// afterwards dials nobody.
    func test_MAC_STACK_06_aPressWaitingOnTheMicrophoneIsDroppedBySleep() async throws {
        let microphone = HeldMicrophone()
        let container = try AppContainer(
            baseURL: XCTUnwrap(URL(string: "https://calls.invalid")),
            microphone: microphone
        )
        let model = DialerModel(container: container, workspaceId: "ws_1", role: .agency)
        model.onEntryChange("+14165550100")

        model.placeCall()
        await waitUntil { microphone.asked }
        XCTAssertTrue(container.callStack.hasLiveCall)

        await container.callStack.endEverything(.sleep)
        XCTAssertFalse(model.placing)
        XCTAssertFalse(container.callStack.hasLiveCall)
        XCTAssertNil(model.refusal, "nobody refused anything")

        microphone.answer(true)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.call, "the late grant dials nobody")
    }
}

/// A microphone whose question stays open until the test answers it.
final class HeldMicrophone: MicrophoneAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Bool, Never>?
    private var wasAsked = false

    var status: MicrophoneStatus {
        .notDetermined
    }

    var asked: Bool {
        lock.withLock { wasAsked }
    }

    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.withLock {
                wasAsked = true
                waiting = continuation
            }
        }
    }

    func answer(_ granted: Bool) {
        let pending: CheckedContinuation<Bool, Never>? = lock.withLock {
            defer { waiting = nil }
            return waiting
        }
        pending?.resume(returning: granted)
    }
}

/// The microphone and speaker pickers' entries.
final class MacAudioDevicePickerTests: XCTestCase {
    private func device(_ id: String, _ name: String) -> AudioDeviceChoice {
        AudioDeviceChoice(id: id, name: name, isDefault: id == AudioDeviceChoice.systemDefaultId)
    }

    /// ⛔ LIVEKIT LISTS THE SYSTEM DEFAULT AS A DEVICE WITH THE ID `default` (measured on the
    /// iMac), so the picker must not offer the default twice.
    func test_MAC_DEVICES_01_theDefaultIsOfferedOnceAndStoredAsEmpty() {
        let entries = AudioDevicePickers.entries(
            [device("default", "Internal Microphone"), device("usb-1", "Desk Headset")],
            selected: ""
        )
        XCTAssertEqual(entries.map(\.label), ["System default", "Desk Headset"])
        XCTAssertEqual(entries.map(\.tag), ["", "usb-1"])
    }

    func test_MAC_DEVICES_02_aRememberedDeviceThatIsNotConnectedSaysSo() {
        let entries = AudioDevicePickers.entries([device("default", "Internal Speakers")], selected: "usb-1")
        XCTAssertEqual(entries.last, AudioDevicePickers.Entry(tag: "usb-1", label: "Not connected"))
    }

    func test_MAC_DEVICES_03_aConnectedChoiceIsNotDuplicated() {
        let entries = AudioDevicePickers.entries([device("usb-1", "Desk Headset")], selected: "usb-1")
        XCTAssertEqual(entries.map(\.tag), ["", "usb-1"])
    }
}
