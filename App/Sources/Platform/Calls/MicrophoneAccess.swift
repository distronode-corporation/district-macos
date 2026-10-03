import AVFoundation

/// Whether this app may use the microphone, as the OS last answered.
///
/// ⚠️ THREE STATES, NOT A BOOL, BECAUSE "NEVER ASKED" IS THE ONE THAT MATTERS. A call's audio
/// engine reads the grant passively and refuses to record without it (LiveKit's WebRTC
/// `AudioEngineDevice` answers `kAudioEngineErrorInsufficientDevicePermission`, and
/// `Room.connect` rethrows it as `deviceAccessDenied`), so a question nobody asked fails a call
/// exactly as a refusal does. Only `notDetermined` can still be fixed by asking.
enum MicrophoneStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

/// The microphone permission, behind a seam.
///
/// ⛔ NOTHING THAT PUBLISHES CALL AUDIO MAY ASSUME THE PROMPT HAPPENED SOMEWHERE ELSE. If only a
/// meeting room and the persona preview asked, then on a fresh install the first dial and the first
/// answer would both fail at the media join: the dial after the carrier had already rung the
/// callee, and the answer after the server had already bridged the caller. So `DialerModel` asks
/// before the carrier hears about a call, and ``IncomingCallModel`` asks at Answer.
///
/// ⚠️ NO QUESTION AT LANDING, UNLIKE iOS. The iOS app asks at the first signed-in screen
/// because an answer from the lock screen, a car or a headset arrives with the app in the
/// background, where no alert can be shown. Every Mac answer arrives with the app running
/// and able to show one: the ring panel's button, or the notification's Answer, which
/// brings the app forward.
///
/// ⚠️ A PROTOCOL SO BOTH CALL MODELS CAN BE DRIVEN WITHOUT A SYSTEM ALERT. It is held by
/// ``CallStack``, the platform half of a call, and injected through ``AppContainer``.
protocol MicrophoneAccess: Sendable {
    /// The grant as the OS holds it now. ⚠️ Passive: reading it never prompts.
    var status: MicrophoneStatus { get }

    /// Ask, or answer at once when the question has already been answered.
    ///
    /// - Returns: whether the microphone may be used.
    func request() async -> Bool
}

/// The real permission.
///
/// ⚠️ `AVCaptureDevice`, NOT `AVAudioApplication`, SO THE APP ASKS ONE WAY. The persona preview
/// and the meeting room already ask through it, and it is the authorization the WebRTC engine
/// checks before it will record.
struct LiveMicrophoneAccess: MicrophoneAccess {
    var status: MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
