import DistrictData
import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The account's two sheets that change the account itself: deleting it, and two-step
/// verification on each of its steps.
///
/// ⚠️ THE FRESH SIGN-IN AT A PROVIDER IS THE ONE SEAM: it opens a browser sheet in the app,
/// so each model here is given one that has already proved it is you
/// (``SSOReauthOutcome/proved(expiresInSeconds:)``). Every request after it goes to the
/// recorded answers, as everywhere else.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class AccountSheetScreenTests: ScreenSnapshotCase {
    /// Each sheet's size at its presentation site on the Account screen.
    private static let deleteSize = CGSize(width: 480, height: 520)
    private static let twoStepSize = CGSize(width: 480, height: 560)

    // MARK: - Delete account

    func testDeleteAccount() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("explain", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.deleteSize
            ) { app in
                await Self.delete(app)
            }
        }
        try await assertView("password-en", rules: ScreenRules.loaded, size: Self.deleteSize) { app in
            await Self.delete(app) { model in model.usePassword() }
        }
        try await assertView(
            "password-refused-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.deleteSize
        ) { app in
            await Self.delete(app) { model in
                model.usePassword()
                model.password = "not-the-password"
                await model.submitPassword()
            }
        }
        try await assertView("confirm-en", rules: ScreenRules.loaded, size: Self.deleteSize) { app in
            await Self.delete(app) { model in
                await model.reauthenticate(with: .google)
            }
        }
        try await assertView(
            "delete-failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.deleteSize
        ) { app in
            await Self.delete(app) { model in
                await model.reauthenticate(with: .google)
                model.confirmation = "founder@contract.test"
                await model.delete()
            }
        }
    }

    /// The delete sheet, its model taken through `prepared` first (it reads nothing on appear).
    private static func delete(
        _ app: SignedInApp,
        prepared: (@MainActor (DeleteAccountModel) async -> Void)? = nil
    ) async -> AnyView {
        let model = DeleteAccountModel(
            repository: NativeReauthRepository(client: app.container.api),
            sso: { _ in .proved(expiresInSeconds: 300) },
            deleted: { _ in }
        )
        await prepared?(model)
        return AnyView(DeleteAccountView(model: model)
            .macSheetSize(width: deleteSize.width, height: deleteSize.height)
            .districtTheme())
    }

    // MARK: - Two-step verification

    /// ⚠️ THE STATUS READ IS `GET /api/auth/mfa`, which the shared rules do not answer (they
    /// answer the native and the older `/status` paths).
    private static let on: [FixtureTransport.Rule] = [
        .get("/api/auth/mfa", .fixture("mobile/district-mfa-status.json")),
    ]

    /// ⚠️ THE RECORDED STATUS IS ON; turning it on starts from off, so these answers say off.
    private static let off: [FixtureTransport.Rule] = [
        .get("/api/auth/mfa", .edited("mobile/district-mfa-status.json") { status in
            status["enrolled"] = false
            status["enrolledAt"] = NSNull()
            status["backupCodesRemaining"] = 0
        }),
        .any("/api/auth/mfa/enroll", .fixture("mobile/district-mfa-enroll.json")),
        .any("/api/auth/mfa/confirm", .fixture("mobile/district-mfa-confirm.json")),
    ]

    func testTwoStepStatus() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("on", locale),
                rules: Self.on + ScreenRules.loaded,
                locale: locale,
                size: Self.twoStepSize
            ) { app in
                Self.twoStep(app, then: nil)
            }
        }
        try await assertView("off-en", rules: Self.off + ScreenRules.loaded, size: Self.twoStepSize) { app in
            Self.twoStep(app, then: nil)
        }
        try await assertView("load-failed-en", rules: ScreenRules.failing, size: Self.twoStepSize) { app in
            Self.twoStep(app, then: nil)
        }
    }

    func testTwoStepEnroll() async throws {
        // Turn on: the ways to confirm it is you, then the password.
        try await assertView("reauth-en", rules: Self.off + ScreenRules.loaded, size: Self.twoStepSize) { app in
            Self.twoStep(app) { model in model.begin(.turnOn) }
        }
        try await assertView("password-en", rules: Self.off + ScreenRules.loaded, size: Self.twoStepSize) { app in
            Self.twoStep(app) { model in
                model.begin(.turnOn)
                model.usePassword()
            }
        }
        // Proved: the QR code and the secret's cards, from the recorded enrolment.
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("scan", locale),
                rules: Self.off + ScreenRules.loaded,
                locale: locale,
                size: Self.twoStepSize
            ) { app in
                Self.twoStep(app) { model in await Self.enroll(model) }
            }
        }
        try await assertView(
            "enroll-failed-en",
            rules: Self.refusingWrites() + Self.off + ScreenRules.loaded,
            size: Self.twoStepSize
        ) { app in
            Self.twoStep(app) { model in await Self.enroll(model) }
        }
    }

    func testTwoStepConfirm() async throws {
        // The code typed and accepted: the recovery codes, shown once.
        try await assertView("codes-en", rules: Self.off + ScreenRules.loaded, size: Self.twoStepSize) { app in
            Self.twoStep(app) { model in
                await Self.enroll(model)
                model.totp = "123456"
                await model.confirm()
            }
        }
        // ⚠️ THE CONFIRM REFUSED, its rule ahead of the recorded enrolment it would otherwise get.
        let refused = Self.writes("/api/auth/mfa/confirm", .status(500)) + Self.off + ScreenRules.loaded
        try await assertView("confirm-failed-en", rules: refused, size: Self.twoStepSize) { app in
            Self.twoStep(app) { model in
                await Self.enroll(model)
                model.totp = "123456"
                await model.confirm()
            }
        }
    }

    func testTwoStepDisable() async throws {
        // Turn off: the ways to confirm it is you, then the password.
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("reauth", locale),
                rules: Self.on + ScreenRules.loaded,
                locale: locale,
                size: Self.twoStepSize
            ) { app in
                Self.twoStep(app) { model in model.begin(.turnOff) }
            }
        }
        try await assertView("password-en", rules: Self.on + ScreenRules.loaded, size: Self.twoStepSize) { app in
            Self.twoStep(app) { model in
                model.begin(.turnOff)
                model.usePassword()
            }
        }
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + Self.on + ScreenRules.loaded,
            size: Self.twoStepSize
        ) { app in
            Self.twoStep(app) { model in
                model.begin(.turnOff)
                await model.reauthenticate(with: .google)
            }
        }
    }

    private static func enroll(_ model: TwoStepModel) async {
        model.begin(.turnOn)
        await model.reauthenticate(with: .google)
    }

    /// The two-step sheet, active (a test host never is, and an inactive app covers the
    /// secret), and `then` run on its model once the sheet's own status read has answered
    /// (``TwoStepModel/load()`` puts the model back on the overview).
    private static func twoStep(
        _ app: SignedInApp,
        then action: (@MainActor (TwoStepModel) async -> Void)?
    ) -> AnyView {
        let model = TwoStepModel(
            settings: TwoStepSettingsRepository(client: app.container.api),
            reauth: NativeReauthRepository(client: app.container.api),
            sso: { _ in .proved(expiresInSeconds: 300) }
        )
        if let action {
            once({ model.step == .overview && !model.busy }, { await action(model) })
        }
        return AnyView(TwoStepView(model: model, appActive: true)
            .macSheetSize(width: twoStepSize.width, height: twoStepSize.height)
            .districtTheme())
    }
}
