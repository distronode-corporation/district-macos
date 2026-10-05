@testable import DistrictMac
import DistrictModel
import XCTest

/// The Mac's own wiring of the Voice Studio: who is offered the row, where the hub row and the
/// persona form's "Open Voice Studio" link go, and the test handles.
///
/// ⚠️ THE STUDIO'S RULES ARE district-core-swift's (`VoiceStudio*Tests`) and the screen model's
/// are `VoiceStudioModelTests`, ported from iOS. What is here is what only the Mac decides.
final class MacVoiceStudioTests: XCTestCase {
    private let roles: [WorkspaceRole?] = WorkspaceRole.allCases.map { Optional($0) } + [nil]

    private func studio(_ role: WorkspaceRole?) -> Route {
        .workspaceSettings(workspaceId: "ws_1", role: role, section: .voiceStudio)
    }

    /// ⛔ THE STUDIO IS HIDDEN EXACTLY WHERE THE PERSONA FORM IS: its read excludes a viewer,
    /// as `persona/options` does, and a row that 403s on open is worse than no row.
    func test_MAC_STUDIO_01_theStudioIsGatedLikeThePersonaForm() {
        for role in roles {
            let persona = Route.workspaceSettings(workspaceId: "ws_1", role: role, section: .persona)
            XCTAssertEqual(
                Self.isHidden(RouteGate.gate(for: studio(role), role: role)),
                Self.isHidden(RouteGate.gate(for: persona, role: role)),
                "role \(String(describing: role))"
            )
        }
    }

    /// ⛔ A ROLE THAT MAY NOT WRITE NEVER SEES THE STUDIO; ONE THAT MAY, DOES.
    func test_MAC_STUDIO_02_onlyAWriterIsOfferedTheStudio() {
        for role in roles {
            XCTAssertEqual(
                Self.isHidden(RouteGate.gate(for: studio(role), role: role)),
                !WorkspaceRole.allowsMutation(role),
                "role \(String(describing: role))"
            )
        }
    }

    /// The hub's row opens the Studio, with the role carried.
    func test_MAC_STUDIO_03_theHubRowOpensTheStudio() {
        let hub = SettingsHubView(workspaceId: "ws_1", role: .agency)
        XCTAssertEqual(hub.destination(.voiceStudio), studio(.agency))
    }

    /// ⛔ THE PERSONA FORM LINKS TO THE STUDIO AND NEVER DRAWS ITS CONTROLS, and it offers the
    /// link only where the Studio's own row would be drawn.
    func test_MAC_STUDIO_04_thePersonaFormLinksToTheStudioWhereItIsOffered() {
        for role in roles {
            let link = PersonaView.voiceStudioRoute(workspaceId: "ws_1", role: role)
            if WorkspaceRole.allowsMutation(role) {
                XCTAssertEqual(link, studio(role), "role \(String(describing: role))")
            } else {
                XCTAssertNil(link, "role \(String(describing: role))")
            }
        }
    }

    /// ⚠️ THE HANDLES ARE ANDROID'S, so one UI walk can address both clients.
    func test_MAC_STUDIO_05_theHandlesAreAndroids() {
        XCTAssertEqual(
            A11yID.VoiceStudio.handle(A11yID.VoiceStudio.recipeKind, "fastest"),
            "district-voice-studio-recipe-fastest"
        )
        XCTAssertEqual(
            A11yID.VoiceStudio.handle(A11yID.VoiceStudio.blockKind, "llm", selected: true),
            "district-voice-studio-block-llm-selected"
        )
        XCTAssertEqual(A11yID.VoiceStudio.root, "district-voice-studio-root")
        XCTAssertNotEqual(A11yID.Persona.openVoiceStudio, A11yID.VoiceStudio.root)
    }

    /// ⛔ THE STUDIO IS A SIBLING OF THE PERSONA FORM, NOT A CHILD: its own settings section,
    /// listed right after it, so a stale persona form can never resend the engine.
    func test_MAC_STUDIO_06_theStudioIsItsOwnSectionAfterThePersona() {
        let sections = SettingsSection.allCases
        let persona = sections.firstIndex(of: .persona)
        let studio = sections.firstIndex(of: .voiceStudio)
        XCTAssertNotNil(persona)
        XCTAssertEqual(studio, persona.map { $0 + 1 })
    }

    /// ⛔ THE HUB'S ROW IS "Voice", UNDER DISTRICT STUDIO, RIGHT AFTER PERSONA, as the web's
    /// District Studio pages are, and the screen it opens is titled the same as the wire heading.
    func test_MAC_STUDIO_07_theHubRowIsVoiceUnderDistrictStudio() throws {
        let studioGroup = try XCTUnwrap(SettingsHubView.groups.first)
        XCTAssertEqual(studioGroup.title, "District Studio")
        let sections = studioGroup.entries.map(\.section)
        let voice = try XCTUnwrap(sections.firstIndex(of: .voiceStudio))
        XCTAssertEqual(sections.firstIndex(of: .persona), voice - 1)
        XCTAssertEqual(studioGroup.entries[voice].title, "Voice")
        XCTAssertEqual(VoiceStudioCopy.title, "Voice")
    }

    private static func isHidden(_ gate: RouteGate) -> Bool {
        if case .hidden = gate {
            return true
        }
        return false
    }
}
