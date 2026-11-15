import AppKit
import DistrictData
import SwiftUI

/// The new secret: its QR code, the key to type by hand, and the code that confirms it.
/// Ported from district-ios.
///
/// ⛔ NOTHING HERE LOGS, PERSISTS OR SHARES THE SECRET. Copy writes it to this Mac's
/// pasteboard only, for two minutes (``TwoStepSecret/copySensitive(_:to:lifetime:)``), and Open
/// hands an `otpauth://` link, and nothing else, to an authenticator app on this Mac; there is no
/// share menu.
///
/// ⚠️ THE CONFIRM BUTTON IS THE SHEET'S DEFAULT, IN ITS BUTTON ROW (``TwoStepView``), so the
/// refusal is drawn here, by the field it is about.
struct TwoStepScanCard: View {
    @Bindable var model: TwoStepModel
    let enrollment: TwoStepModel.Enrollment

    @State private var copied = false
    @State private var openFailed = false
    @FocusState private var focused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        TwoStepCard {
            DistrictEyebrow(text: TwoStepCopy.scanTitle)
            TwoStepParagraph(text: TwoStepCopy.scanIntro)
            qrCode
            Text(TwoStepCopy.keyLabel)
                .font(DistrictType.labelLarge)
                .foregroundStyle(colors.foreground)
            TwoStepSecretText(text: TwoStepSecret.grouped(enrollment.secret))
                .accessibilityLabel(TwoStepCopy.keyLabel)
                .accessibilityValue(enrollment.secret)
                .accessibilityIdentifier(A11yID.TwoStep.secret)
            HStack(spacing: DistrictSpacing.tight) {
                Button(copied ? TwoStepCopy.copied : TwoStepCopy.copyKey) {
                    TwoStepSecret.copySensitive(enrollment.secret)
                    copied = true
                }
                .buttonStyle(.districtSecondary)
                .accessibilityIdentifier(A11yID.TwoStep.copyKey)
                Button(TwoStepCopy.openAuthenticator, action: open)
                    .buttonStyle(.districtSecondary)
                    .accessibilityIdentifier(A11yID.TwoStep.openAuthenticator)
            }
            if openFailed {
                TwoStepParagraph(text: TwoStepCopy.openFailed)
            }
            TwoStepParagraph(text: TwoStepCopy.codePrompt)
            TextField(MfaCopy.authenticatorPlaceholder, text: $model.totp)
                // ⛔ `.oneTimeCode` lets AutoFill offer the code from Passwords.
                .textContentType(.oneTimeCode)
                .districtField()
                .focused($focused)
                .disabled(model.busy)
                .onSubmit(confirm)
                .accessibilityIdentifier(A11yID.TwoStep.totp)
            if let failure = model.failure {
                Text(failure)
                    .font(DistrictType.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Tone.warning.ink(colors))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(A11yID.TwoStep.message)
            }
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let png = enrollment.qrPNG, let image = PlatformImage(data: png) {
            Image(platformImage: image)
                // ⚠️ NEAREST-NEIGHBOUR: a smoothed QR code blurs its modules and scans worse.
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200)
                // ⚠️ THE SERVICE DRAWS DARK ON LIGHT: a white quiet zone keeps it scannable in dark mode.
                .padding(DistrictSpacing.tight)
                .background(Color.white, in: RoundedRectangle(cornerRadius: DistrictRadius.control))
                .frame(maxWidth: .infinity)
                .privacySensitive()
                .accessibilityLabel(TwoStepCopy.qrLabel)
                .accessibilityIdentifier(A11yID.TwoStep.qr)
        } else {
            TwoStepParagraph(text: TwoStepCopy.qrUnreadable)
        }
    }

    private func confirm() {
        Task { await model.confirm() }
    }

    private func open() {
        guard let url = TwoStepSecret.authenticatorURL(enrollment.otpauthURI) else {
            openFailed = true
            return
        }
        openURL(url) { accepted in openFailed = !accepted }
    }
}

/// The recovery codes, this once, with Copy all and the warning that they are not shown again.
///
/// ⚠️ "I have saved them" IS THE SHEET'S DEFAULT BUTTON, in its button row (``TwoStepView``).
struct TwoStepCodesCard: View {
    let model: TwoStepModel

    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        TwoStepCard {
            DistrictEyebrow(text: TwoStepCopy.codesTitle)
            Text(TwoStepCopy.codesWarning)
                .font(DistrictType.bodySmall)
                .foregroundStyle(Tone.warning.ink(colors))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            TwoStepSecretText(text: model.recoveryCodes.joined(separator: "\n"))
                .accessibilityIdentifier(A11yID.TwoStep.codes)
            Button(copied ? TwoStepCopy.copied : TwoStepCopy.copyAll) {
                TwoStepSecret.copySensitive(model.recoveryCodes.joined(separator: "\n"))
                copied = true
            }
            .buttonStyle(.districtSecondary)
            .accessibilityIdentifier(A11yID.TwoStep.copyCodes)
        }
    }
}

/// What the two cards do with a secret besides drawing it.
@MainActor
enum TwoStepSecret {
    /// How long a copied secret stays on the pasteboard, as on iOS.
    static let pasteboardLifetime: Duration = .seconds(120)

    /// ⛔ AppKit's marker types for a password manager's copy (nspasteboard.org): a clipboard
    /// history keeps neither a concealed nor a transient item.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// The key in groups of four, as authenticator apps print it. ⚠️ Display only: Copy and
    /// VoiceOver read the key as the service sent it.
    static func grouped(_ secret: String) -> String {
        stride(from: 0, to: secret.count, by: 4).map { start in
            let from = secret.index(secret.startIndex, offsetBy: start)
            let to = secret.index(from, offsetBy: 4, limitedBy: secret.endIndex) ?? secret.endIndex
            return String(secret[from ..< to])
        }.joined(separator: " ")
    }

    /// The last copy that has not expired yet, for ``expireOnQuit()``.
    private static var pending: (pasteboard: NSPasteboard, written: Int)?

    /// ⛔ THIS MAC ONLY, AND FOR TWO MINUTES: never Universal Clipboard (`.currentHostOnly`,
    /// iOS's `.localOnly`), never a clipboard history (the concealed and transient markers),
    /// and not left on the pasteboard for whatever is pasted next week. `NSPasteboard` has no
    /// expiry of its own (iOS's `.expirationDate`), so the copy is cleared after `lifetime`
    /// unless something else was copied since, and at the latest when the app quits
    /// (``expireOnQuit()``), since the timer dies with the process (Seer and cubic on #112).
    ///
    /// ⚠️ `clearContents()` IS PART OF `prepareForNewContents(with:)`, so no older type is left
    /// beside the secret (see ``Clipboard``).
    @discardableResult
    static func copySensitive(
        _ text: String,
        to pasteboard: NSPasteboard = .general,
        lifetime: Duration = pasteboardLifetime
    ) -> Int {
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: concealedType)
        pasteboard.setData(Data(), forType: transientType)
        let written = pasteboard.changeCount
        pending = (pasteboard, written)
        Task { @MainActor in
            try? await Task.sleep(for: lifetime)
            expire(pasteboard, written: written)
        }
        return written
    }

    /// Clears the secret ``copySensitive(_:to:lifetime:)`` wrote, unless the pasteboard has
    /// changed since. ⚠️ A newer copy (of anything) is never cleared.
    static func expire(_ pasteboard: NSPasteboard, written: Int) {
        if pending?.pasteboard === pasteboard, pending?.written == written {
            pending = nil
        }
        guard pasteboard.changeCount == written else { return }
        pasteboard.clearContents()
    }

    /// The app is quitting: the copy that has not expired yet goes now (``AppDelegate``).
    static func expireOnQuit() {
        guard let pending else { return }
        expire(pending.pasteboard, written: pending.written)
    }

    /// The link Open hands over, ONLY when it is an `otpauth://` link (cubic on #112): an
    /// enrolment answer that named another scheme must never open a browser, a file or another
    /// app.
    static func authenticatorURL(_ uri: String) -> URL? {
        guard let url = URL(string: uri), url.scheme?.lowercased() == "otpauth" else { return nil }
        return url
    }
}

// ── Pieces shared by the sheet and its cards ─────────────────────────────────

/// A secret in a monospaced, privacy-sensitive box.
///
/// ⛔ NOT SELECTABLE, where iOS's is (cubic on #112): a ⌘C on the Mac would write it to the
/// general pasteboard for good and to Universal Clipboard. The Copy buttons are the one way out,
/// through ``TwoStepSecret/copySensitive(_:to:lifetime:)``.
struct TwoStepSecretText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DistrictColors.resolve(colorScheme)
        Text(text)
            .font(DistrictType.bodySmall)
            .monospaced()
            .foregroundStyle(colors.foreground)
            .padding(DistrictSpacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.muted, in: RoundedRectangle(cornerRadius: DistrictRadius.control))
            .privacySensitive()
    }
}

struct TwoStepParagraph: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(DistrictType.bodySmall)
            .foregroundStyle(DistrictColors.resolve(colorScheme).foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TwoStepCard<Rows: View>: View {
    private let rows: Rows

    init(@ViewBuilder rows: () -> Rows) {
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.row) {
            rows
        }
        .padding(DistrictSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .districtCardSurface()
    }
}
