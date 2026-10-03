import SwiftUI

/// The detail of a section whose screens have not been ported to the Mac yet.
///
/// ⚠️ A SCAFFOLD, AND IT SAYS SO. Each section is replaced by its port of the iPad screen
/// in the wave ``SidebarItem/portedInWave`` names; this view is deleted when the last one
/// lands. Until then the section is reachable on the web dashboard.
struct ComingLaterView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title2.weight(.semibold))
            Text(Self.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static let caption = "Coming in a later wave"
}
