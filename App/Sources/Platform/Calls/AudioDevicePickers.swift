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

    /// One picker entry: what is stored when it is chosen, and what it says.
    struct Entry: Equatable, Identifiable {
        let tag: String
        let label: String

        var id: String {
            tag
        }
    }

    /// The entries one picker offers: the system default first (stored as the empty
    /// string), every particular device, and a remembered device that is not connected.
    static func entries(_ choices: [AudioDeviceChoice], selected: String) -> [Entry] {
        var entries = [Entry(tag: "", label: systemDefault)]
        entries += choices.filter { !$0.isSystemDefault }.map { Entry(tag: $0.id, label: $0.name) }
        if !selected.isEmpty, !choices.contains(where: { $0.id == selected }) {
            entries.append(Entry(tag: selected, label: disconnected))
        }
        return entries
    }

    private func options(_ choices: [AudioDeviceChoice], selected: String) -> some View {
        ForEach(Self.entries(choices, selected: selected)) { entry in
            Text(entry.label).tag(entry.tag)
        }
    }

    private var inputBinding: Binding<String> {
        Binding(get: { devices.selectedInput }, set: { devices.selectInput($0) })
    }

    private var outputBinding: Binding<String> {
        Binding(get: { devices.selectedOutput }, set: { devices.selectOutput($0) })
    }
}
