import DistrictL10n
@testable import DistrictMac
import DistrictNetwork
import Foundation

/// What the sheet snapshot tests share: rules for the writes a sheet sends, and a way to act
/// on a sheet after its own `.task` has read, as the person at the keyboard would.
extension ScreenSnapshotCase {
    /// Every write (POST, PUT, PATCH, DELETE) to a path matched whole by `pattern`, answered
    /// with `reply`. Put first in a screen's rules, so it wins over the reads after it.
    static func writes(_ pattern: String, _ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        [HTTPMethod.post, .put, .patch, .delete].map { method in
            FixtureTransport.Rule(method: method, pattern: pattern, op: nil, reply: reply)
        }
    }

    /// Every write anywhere refused with `status`: a sheet's save-failure state.
    static func refusingWrites(_ status: Int = 500) -> [FixtureTransport.Rule] {
        writes(".*", .status(status))
    }

    /// Run `action` once `ready` holds, without waiting for it here.
    ///
    /// ⚠️ FOR A SHEET THAT READS IN ITS OWN `.task` AND RESETS ITSELF THERE (the compose and
    /// two-step sheets): a model prepared before the view appears is put back to its first
    /// state by that read, so the step a test wants is taken after it, as a click would be.
    /// The harness waits for the requests the action sends like any other.
    ///
    /// ⚠️ BOUNDED: after 10 seconds the action runs anyway, and the image shows why.
    static func once(_ ready: @escaping @MainActor () -> Bool, _ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(10)
            while !ready(), Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            await action()
        }
    }

    /// The image name for `state` in `locale`: `new-en`, `new-fr`.
    static func named(_ state: String, _ locale: L10nLocale) -> String {
        "\(state)-\(locale == .en ? "en" : "fr")"
    }
}
