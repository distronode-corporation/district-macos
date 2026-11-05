import DistrictData
import PhotosUI
import SwiftUI

// The reply box's constants, the two attachment readers and the three bindings, apart from
// ``ComposerBar`` for SwiftLint's `file_length`. ⚠️ The bindings moved verbatim when the
// WhatsApp window joined the box (8.2.0); they lost `private` only because it is file-scoped.

extension ComposerBar {
    /// ⛔ THE SEND KEY: ⌘↩ (``KeyboardShortcut/districtSubmit``), never `.defaultAction`, which
    /// is a bare Return. `ComposerSendKeyTests` pins it.
    static let sendShortcut = KeyboardShortcut.districtSubmit

    /// Send's help tag: its name and the key that sends, in the Mac's own glyphs, which read
    /// the same in either language.
    static func sendHelp(_ title: String) -> String {
        "\(title) (\u{2318}\u{21A9})"
    }

    /// The tallest the reply box grows before it scrolls.
    static let fieldMaxLines = 5

    /// The text view's own line-fragment padding, which the placeholder and the sizing text
    /// match so the three line up.
    static let editorInset: CGFloat = 5

    /// How much narrower the sizing text is than the editor's line, so it wraps first.
    static let sizingSlack: CGFloat = 8

    /// The words the box is sized by: the reply, with a trailing space so a new line the
    /// person has just typed already has its height, and one line when it is empty.
    static func sizingText(_ reply: String) -> String {
        reply + " "
    }

    /// Read the picked item's bytes and hand them to the model.
    ///
    /// ⛔ THE BYTES CROSS INTO THE MODEL THROUGH ONE `@MainActor` CALL and nothing
    /// else is carried across: `Data` is a value, the model owns every decision about
    /// it, and the type and size are refused there before a byte is uploaded.
    ///
    /// ⚠️ A NIL OR THROWING LOAD IS "COULD NOT BE READ", WHICH IS NOT THE SAME AS A
    /// REJECTED TYPE OR SIZE. Those three call for three different next actions from
    /// the operator, and collapsing them would leave them re-picking the same file.
    func read(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.refuseAttachment(ThreadModel.unreadableAttachment)
            return
        }
        await model.attach(data, mimeType: item.preferredMIMEType(allowed: MediaUploadLimits.allowedMimeTypes))
    }

    /// Read a file chosen in the open panel and hand it to the model, as ``read(_:)`` does.
    ///
    /// ⛔ THE SECURITY-SCOPED ACCESS IS OPENED AND CLOSED AROUND THE ONE READ. The sandbox
    /// grants this app the chosen file only (`files.user-selected.read-write`), and the
    /// grant is through the URL's scope; reading outside it fails as "could not be read".
    func readFile(_ result: Result<URL, any Error>) async {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            model.refuseAttachment(ThreadModel.unreadableAttachment)
            return
        }
        await model.attach(
            data,
            mimeType: AttachmentFile.mimeType(of: url, allowed: MediaUploadLimits.allowedMimeTypes)
        )
    }

    // MARK: - Wiring

    var text: Binding<String> {
        Binding(
            get: { model.composerText },
            set: { model.composerTextChanged($0) }
        )
    }

    /// ⚠️ THROUGH ``ThreadModel/subjectChanged(_:)`` FOR THE REASON ``text`` GOES
    /// THROUGH ``ThreadModel/composerTextChanged(_:)``: that method is the only one
    /// that arms an autosave, and there must be no second copy of this string.
    var subject: Binding<String> {
        Binding(
            get: { model.composerSubject },
            set: { model.subjectChanged($0) }
        )
    }

    /// Which of the thread's channels the next send uses.
    ///
    /// ⛔ THROUGH ``ThreadModel/selectReplyTarget(_:)`` AND NOWHERE ELSE, for the same
    /// class of reason the two bindings above go through their own methods: that
    /// method is the only thing that drops staged images when the channel stops being
    /// able to carry them and writes the note saying so. A binding straight to the
    /// index would move the channel and leave the images attached to a send that
    /// silently ignores them.
    ///
    /// ⚠️ A CLOSURE LITERAL, NEVER A BARE METHOD REFERENCE. A bare
    /// MainActor-isolated method as a `Binding` setter aborts the compiler in IRGen
    /// under Swift 6 with no `error:` line; `.swiftlint.yml`'s one custom rule exists
    /// for exactly this.
    var selectedChannel: Binding<Int> {
        Binding(
            get: { model.selectedReplyIndex },
            set: { model.selectReplyTarget($0) }
        )
    }
}
