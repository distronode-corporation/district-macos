import SwiftUI

/// The microphone and speaker pickers, in a call and in Settings.
///
/// ⚠️ MAC ONLY, AND THE ANSWER TO iOS'S SPEAKER TOGGLE. A phone switches between its
/// earpiece and its loudspeaker; a Mac has neither, and the person chooses among the
/// devices attached to it. The choice goes through LiveKit's `AudioManager` (see
/// ``AudioDevices``), so it moves a call that is already up and sticks for the next one.
///
/// ⚠️ THE LISTS ARE READ WHEN THE PICKERS APPEAR, which is the first moment this app
/// touches LiveKit's audio stack outside a call.
struct AudioDevicePickers: View {
    let devices: AudioDevices

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
            Picker(Self.microphoneLabel, selection: inputBinding) {
                options(devices.inputs, selected: devices.selectedInput)
            }
            Picker(Self.speakerLabel, selection: outputBinding) {
                options(devices.outputs, selected: devices.selectedOutput)
            }
        }
        .frame(maxWidth: 360)
        .onAppear { devices.refresh() }
    }

    static let microphoneLabel = "Microphone"
    static let speakerLabel = "Speaker"
    /// What the default entry is called. ⚠️ It follows the system's choice, which changes
    /// when a headset is plugged in, so it is named for that rather than for a device.
    static let systemDefault = "System default"
    /// ⚠️ A REMEMBERED DEVICE THAT IS NOT CONNECTED STAYS SELECTED, NAMED AS ABSENT, rather
    /// than the picker silently showing the default: the next call will use the default,
    /// and the person should be able to see why.
    static let disconnected = "Not connected"

    @ViewBuilder
    private func options(_ choices: [AudioDeviceChoice], selected: String) -> some View {
        Text(Self.systemDefault).tag("")
        ForEach(choices.filter { !$0.id.isEmpty }) { choice in
            Text(choice.name).tag(choice.id)
        }
        if !selected.isEmpty, !choices.contains(where: { $0.id == selected }) {
            Text(Self.disconnected).tag(selected)
        }
    }

    private var inputBinding: Binding<String> {
        Binding(get: { devices.selectedInput }, set: { devices.selectInput($0) })
    }

    private var outputBinding: Binding<String> {
        Binding(get: { devices.selectedOutput }, set: { devices.selectOutput($0) })
    }
}
