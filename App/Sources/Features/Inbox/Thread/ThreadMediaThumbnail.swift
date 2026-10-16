import SwiftUI

/// One attachment, drawn as a thumbnail.
///
/// ⛔ `AsyncImage` GOES THROUGH `URLSession.shared` AND THEREFORE CARRIES NO BEARER
/// TOKEN, WHICH IS EXACTLY RIGHT HERE. `/api/media/<uuid>` is an ANONYMOUS capability
/// URL, it must be, because a carrier's MMS fetcher has no session either, so
/// attaching this client's access token would send a credential to a route that never
/// asked for one.
///
/// ⛔ THREE STATES, AND "unavailable" IS NOT ALLOWED TO LOOK LIKE "loading". A
/// permanent shimmer for an image that will never arrive is the worst of the three
/// outcomes: the operator waits for something that is not coming.
struct ThreadMediaThumbnail: View {
    let url: String
    /// The thumbnail's width: 96pt in the conversation, ``stagedSide`` in the composer.
    var side: CGFloat = 96

    /// A staged attachment in the composer: small, as Mail and Messages stage one.
    static let stagedSide: CGFloat = 56

    /// ⚠️ BELOW THIS A SENTENCE DOES NOT FIT, so the two text states draw a symbol and keep
    /// the sentence as its spoken label and its tooltip.
    private static let captionFloor: CGFloat = 80

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                caption(InboxCopy.imageUnavailable)
            case .empty:
                caption(InboxCopy.loadingImage)
            @unknown default:
                caption(InboxCopy.imageUnavailable)
            }
        }
        // ⛔ `minHeight`, BECAUSE THIS BOX HOLDS TEXT IN TWO OF ITS FOUR STATES.
        // A successful image is 96x96; a failure or a load shows `caption("Image
        // unavailable")` / `("Loading image")`, and at an accessibility size that
        // sentence is taller than 96pt and was clipped to nothing. The WIDTH stays
        // fixed so the thumbnail column keeps its rhythm.
        .frame(width: side)
        .frame(minHeight: side)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: DistrictRadius.control))
    }

    @ViewBuilder
    private func caption(_ text: String) -> some View {
        if side < Self.captionFloor {
            Image(systemName: text == InboxCopy.loadingImage ? "photo" : "exclamationmark.triangle")
                .foregroundStyle(colors.mutedForeground)
                .help(text)
                .accessibilityLabel(text)
        } else {
            Text(text)
                .font(DistrictType.caption)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(DistrictSpacing.hairline)
        }
    }
}
