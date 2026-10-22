import DistrictL10n
@testable import DistrictMac
import XCTest

/// A room or a persona preview that ends on its own says the catalog's sentence, never the
/// SDK's (3.0.3).
///
/// ⛔ `.droppedRemotely` and `.failed` carry LiveKit's English error description: "Room
/// deleted" when the room went. ``RoomEngine`` logs it; the banner and the preview's status
/// line say the catalog's words, in English and in French, as the call screens have since
/// 3.0.1 (`CallEndWordingTests`).
final class RoomEndWordingTests: XCTestCase {
    private func french<T>(_ body: () -> T) -> T {
        L10nRuntime.withLocale(.frCA, body)
    }

    func testARoomDeletedDropReadsAsTheCatalogsSentenceInBothLanguages() {
        let phase = RoomPhase.droppedRemotely(reason: "Room deleted")

        XCTAssertEqual(RoomBanner.of(phase)?.text, "You were disconnected from this room.")
        XCTAssertEqual(french { RoomBanner.of(phase)?.text }, "Votre connexion à cette salle a été coupée.")
    }

    func testAnSDKFailureInARoomReadsAsTheCatalogsSentenceInBothLanguages() {
        let phase = RoomPhase.failed(message: "Room deleted")

        XCTAssertEqual(RoomBanner.of(phase)?.text, "The connection to this room was lost.")
        XCTAssertEqual(french { RoomBanner.of(phase)?.text }, "La connexion à cette salle a été perdue.")
    }

    func testARoomDeletedPreviewEndReadsAsTheCatalogsSentenceInBothLanguages() {
        let ending = PersonaPreviewEnding.droppedRemotely(reason: "Room deleted")

        XCTAssertEqual(PersonaPreviewView.endingText(ending), "The preview ended without being stopped here.")
        XCTAssertEqual(
            french { PersonaPreviewView.endingText(ending) },
            "L'aperçu a pris fin sans avoir été arrêté ici."
        )
    }
}
