import SwiftUI

/// "Ring on this computer", with what it does and, when calls cannot ring here, why.
///
/// ⚠️ MAC ONLY, IN TWO PLACES: Account (beside "Calls to you", which decides whether calls
/// are handed to this member at all) and the Settings window (with the microphone and
/// speaker). One view, so the two cannot word it differently. The setting and the line
/// under it are district-linux's (see ``DesktopLiveCopy``).
struct RingHereToggle: View {
    let live: DesktopLive

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
            // ⚠️ A SWITCH, LIKE EVERY OTHER SETTING IN THE APP (Account's "Calls to you", the
            // Settings window's update check): the macOS default is a checkbox, which beside the
            // availability switch read as a different kind of control. The label takes the
            // width so the switch sits at the trailing edge, as that row's does.
            Toggle(isOn: binding) {
                Text(DesktopLiveCopy.settingLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier(A11yID.Account.ringHere)
            Text(DesktopLiveCopy.settingBody)
                .font(DistrictType.caption)
                .foregroundStyle(DistrictColors.resolve(colorScheme).mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let message = DesktopLiveCopy.message(live.status) {
                Text(message)
                    .font(DistrictType.caption)
                    .foregroundStyle(DistrictColors.resolve(colorScheme).warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(get: { live.ringHere }, set: { live.setRingHere($0) })
    }
}
