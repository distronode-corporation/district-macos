import DistrictData
import DistrictModel
import Foundation
import Observation

/// The account's signed-in installs, and signing one of them out.
///
/// ⚠️ A FIRST CUT OF THE iOS DevicesModel: the list and a per-row sign-out. "Sign out
/// everywhere" and the notices arrive with the full port in Wave 5.
///
/// ⛔ SIGNING OUT THIS MAC IS NOT OFFERED AS A ROW ACTION: the server cannot tell this
/// process its credential died, so it goes through the real sign-out (Account > Sign
/// Out), which also unregisters push and wipes the keychain.
@MainActor
@Observable
final class DevicesModel {
    enum State {
        case loading
        case loaded([DeviceSession])
        case failed(FailureText)
    }

    private(set) var state: State = .loading
    /// The device whose sign-out is in flight, so its row cannot be pressed twice.
    private(set) var revoking: String?
    private(set) var notice: String?

    let thisDeviceId: String
    private let devices: DevicesRepository

    init(container: AppContainer) {
        devices = container.devices
        thisDeviceId = container.deviceId
    }

    func load() async {
        switch await devices.list() {
        case let .success(list):
            state = .loaded(list)
        case let .failure(error):
            state = .failed(FailureText.from(error))
        }
    }

    /// ⛔ SINGLE-FLIGHT PER MODEL: a second press while one sign-out runs is dropped.
    func revoke(deviceId: String) async {
        guard revoking == nil, deviceId != thisDeviceId else { return }
        revoking = deviceId
        notice = nil
        defer { revoking = nil }
        switch await devices.revoke(deviceId: deviceId) {
        case .success:
            await load()
        case let .failure(error):
            notice = FailureText.from(error).message
        }
    }

    /// The row's label: the name the device sent, else its platform.
    nonisolated static func label(for device: DeviceSession) -> String {
        if let name = device.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return platformName(device.platform)
    }

    /// ⚠️ An unknown platform is shown as sent rather than guessed at.
    nonisolated static func platformName(_ wire: String) -> String {
        switch wire {
        case "ios": "iPhone or iPad"
        case "android": "Android"
        case "linux": "Linux"
        case "macos": "Mac"
        default: wire
        }
    }
}
