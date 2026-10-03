import Foundation
import LiveKit
import Observation

/// One microphone or speaker, as the pickers show it.
struct AudioDeviceChoice: Identifiable, Hashable, Sendable {
    /// LiveKit's device id.
    ///
    /// ⚠️ LIVEKIT LISTS THE SYSTEM DEFAULT AS A DEVICE OF ITS OWN, WITH THE ID `default`
    /// (measured on an iMac with one microphone: the list was `Internal Microphone`, id
    /// `default`). The pickers show that entry as "System default" (``isSystemDefault``)
    /// and store it as the empty string, so a remembered choice of "the default" follows
    /// the system rather than pinning whichever device was default at the time.
    let id: String
    let name: String
    let isDefault: Bool

    /// LiveKit's id for the system default device. See ``id``.
    static let systemDefaultId = "default"

    /// Whether this entry is the system default rather than a particular device.
    var isSystemDefault: Bool {
        id.isEmpty || id == Self.systemDefaultId
    }
}

/// The microphone and speaker calls and rooms use, chosen through LiveKit's
/// `AudioManager`.
///
/// ⛔ LIVEKIT'S `AudioManager`, NEVER `AVAudioSession` OR CORE AUDIO DIRECTLY. On macOS the
/// SDK's audio device module owns capture and playout for every `Room` in the process;
/// selecting a device anywhere else would change the system default for every other app
/// and still not move a call that is already up. `AudioManager.shared.inputDevice` and
/// `outputDevice` move the live call and the next one alike.
///
/// ⛔ THE CHOICE IS REMEMBERED PER INSTALLATION AND APPLIED AT EACH JOIN, by device id.
/// A headset unplugged since is simply absent from the list, and the system default is
/// used instead of failing the call: ``applySavedChoice()`` never throws and never
/// blocks a join on a device that is not there.
///
/// ⚠️ LAZY. Reading a device list initialises LiveKit's WebRTC audio stack, which costs
/// something and is pointless for a person who never opens a call; nothing here touches
/// the SDK until a picker appears or a call joins.
///
/// ⚠️ THE SETTERS RUN OFF THE MAIN ACTOR. The SDK documents device selection as blocking
/// the calling thread until WebRTC's worker thread applies it, which on the main actor
/// would freeze the window for as long as the audio stack is busy.
@MainActor
@Observable
final class AudioDevices {
    /// The UserDefaults keys. ⚠️ Per installation, like "Ring on this computer": a
    /// headset belongs to this Mac, not to the account.
    static let inputKey = "audio.inputDeviceId"
    static let outputKey = "audio.outputDeviceId"

    private(set) var inputs: [AudioDeviceChoice] = []
    private(set) var outputs: [AudioDeviceChoice] = []

    /// The device each picker shows as chosen. The empty string is the system default.
    private(set) var selectedInput: String
    private(set) var selectedOutput: String

    private let defaults: UserDefaults
    private var observing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedInput = defaults.string(forKey: Self.inputKey) ?? ""
        selectedOutput = defaults.string(forKey: Self.outputKey) ?? ""
    }

    /// Read the device lists, and keep them current while the app runs.
    ///
    /// ⚠️ CALLED BY EVERY PICKER WHEN IT APPEARS; the observer is installed once.
    func refresh() {
        let manager = AudioManager.shared
        inputs = manager.inputDevices.map(Self.choice)
        outputs = manager.outputDevices.map(Self.choice)
        guard !observing else { return }
        observing = true
        // ⚠️ THE SDK CALLS THIS ON ITS OWN THREAD; the lists are re-read on the main actor.
        manager.onDeviceUpdate = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Choose the microphone, for the live call and every later one.
    func selectInput(_ id: String) {
        selectedInput = id
        defaults.set(id, forKey: Self.inputKey)
        Task.detached { Self.apply(input: id) }
    }

    /// Choose the speaker, for the live call and every later one.
    func selectOutput(_ id: String) {
        selectedOutput = id
        defaults.set(id, forKey: Self.outputKey)
        Task.detached { Self.apply(output: id) }
    }

    /// Put the remembered devices back before a join. ⚠️ Off the main actor, and awaited,
    /// so the join captures from the chosen microphone from its first frame.
    func applySavedChoice() async {
        let input = selectedInput
        let output = selectedOutput
        await Task.detached {
            Self.apply(input: input)
            Self.apply(output: output)
        }.value
    }

    /// ⛔ A REMEMBERED DEVICE THAT IS NOT CONNECTED NOW IS SKIPPED, NOT FORCED: the SDK is
    /// left on whatever it holds, which is the system default unless someone chose
    /// otherwise this run. The empty id is the default device itself.
    private nonisolated static func apply(input id: String) {
        let manager = AudioManager.shared
        let device = id.isEmpty ? manager.defaultInputDevice : manager.inputDevices.first { $0.deviceId == id }
        guard let device else { return }
        manager.inputDevice = device
    }

    private nonisolated static func apply(output id: String) {
        let manager = AudioManager.shared
        let device = id.isEmpty ? manager.defaultOutputDevice : manager.outputDevices.first { $0.deviceId == id }
        guard let device else { return }
        manager.outputDevice = device
    }

    private static func choice(_ device: AudioDevice) -> AudioDeviceChoice {
        AudioDeviceChoice(id: device.deviceId, name: device.name, isDefault: device.isDefault)
    }
}
