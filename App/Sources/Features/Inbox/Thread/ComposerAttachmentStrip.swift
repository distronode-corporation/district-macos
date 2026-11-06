import SwiftUI

/// The images in the reply box: the ones the next send carries, then the ones the draft holds.
///
/// ⚠️ ALREADY UPLOADED, so removing one costs nothing server-side and the send carries only
/// URLs. Uploading at PICK time rather than at SEND time means an upload failure costs a retry
/// of one image instead of failing a billable send that has already spent its rate-limit slot.
///
/// ⚠️ SMALL, WITH THE REMOVE CONTROL ON THE THUMBNAIL, as Mail and Messages stage an
/// attachment: a 96pt thumbnail over a "Remove" button was the tallest thing in the box.
///
/// ⛔ HELD IMAGES ARE DRAWN, DIMMED AND MARKED HELD, EACH WITH ITS OWN REMOVE (max review, #95;
/// Sean, "Dimmed chips with Remove"). They sit in the draft on a channel that cannot carry them
/// (``ThreadContent/heldAttachments``), and nothing showed them, so the operator could neither
/// see nor drop what the draft was keeping. VoiceOver hears the channel they are not sent on.
/// They draw on any channel, a thread with no SMS reply included, and a switch to SMS makes
/// them ordinary attachments again.
///
/// ⚠️ A FILE OF ITS OWN BECAUSE `ComposerBar.swift` SITS NEAR THE 500-LINE `file_length`
/// CEILING `swiftlint --strict` ENFORCES.
struct ComposerAttachmentStrip: View {
    let model: ThreadModel
    let content: ThreadContent

    @Environment(\.colorScheme) private var colorScheme

    /// How far a held image is dimmed. ⚠️ The image only: the word Held and Remove keep full ink.
    static let heldOpacity = 0.4

    var body: some View {
        if !content.attachments.isEmpty || !content.heldAttachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: DistrictSpacing.tight) {
                    ForEach(content.attachments, id: \.self) { url in
                        chip(url) {
                            ThreadMediaThumbnail(url: url, side: ThreadMediaThumbnail.stagedSide)
                        }
                    }
                    ForEach(content.heldAttachments, id: \.self) { url in
                        // ⚠️ THE WORD UNDER THE THUMBNAIL, NOT ON IT: « En attente » is wider than
                        // a 56pt staged image.
                        VStack(spacing: 2) {
                            chip(url) {
                                ThreadMediaThumbnail(url: url, side: ThreadMediaThumbnail.stagedSide)
                                    .opacity(Self.heldOpacity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(model.heldAttachmentLabel)
                                    .help(model.heldAttachmentLabel)
                            }
                            Text(InboxCopy.attachmentHeld)
                                .font(DistrictType.caption)
                                .foregroundStyle(DistrictColors.resolve(colorScheme).mutedForeground)
                                .fixedSize()
                                .accessibilityHidden(true)
                        }
                    }
                }
                // ⚠️ ROOM FOR THE REMOVE CONTROL'S EDGE, which a scroll view would clip.
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ url: String, @ViewBuilder thumbnail: () -> some View) -> some View {
        thumbnail()
            .overlay(alignment: .topTrailing) {
                Button(InboxCopy.removeAttachment, systemImage: "xmark.circle.fill") {
                    model.removeAttachment(url)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .buttonName(InboxCopy.removeAttachment)
                .padding(2)
            }
    }
}
