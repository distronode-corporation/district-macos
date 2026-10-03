import DistrictModel
import SwiftUI

/// Who is signed in, which workspace is selected, this Mac's notifications, the account's
/// devices, and Sign Out.
///
/// ⚠️ A FIRST CUT OF THE iOS AccountView plus its Devices screen, on one page because a
/// Mac window has the room. The full port (availability, the push status copy) is Wave 5.
struct AccountView: View {
    let container: AppContainer
    let session: SessionModel
    let workspaceSession: WorkspaceSessionModel
    let push: PushRegistrar

    @State private var devices: DevicesModel

    init(container: AppContainer, session: SessionModel, workspaceSession: WorkspaceSessionModel, push: PushRegistrar) {
        self.container = container
        self.session = session
        self.workspaceSession = workspaceSession
        self.push = push
        _devices = State(initialValue: DevicesModel(container: container))
    }

    var body: some View {
        Form {
            workspaceSection
            notificationsSection
            devicesSection
            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
                .disabled(session.isBusy)
            }
            aboutSection
        }
        .formStyle(.grouped)
        .navigationSubtitle("Account")
        .task { await devices.load() }
    }

    private var workspaceSection: some View {
        Section("Workspace") {
            if workspaceSession.workspaces.count > 1 {
                Picker("Workspace", selection: workspaceBinding) {
                    ForEach(workspaceSession.workspaces, id: \.id) { entry in
                        Text(entry.name).tag(Optional(entry.id))
                    }
                }
            } else {
                LabeledContent("Workspace", value: workspaceSession.selectedEntry?.name ?? "None")
            }
            LabeledContent("Role", value: workspaceSession.role?.wireValue.capitalized ?? "Unknown")
        }
    }

    private var workspaceBinding: Binding<String?> {
        Binding(
            get: { workspaceSession.workspaceId },
            set: { next in
                guard let next, next != workspaceSession.workspaceId else { return }
                Task { await workspaceSession.select(next) }
            }
        )
    }

    private var notificationsSection: some View {
        Section("Notifications on this Mac") {
            LabeledContent("Permission", value: Self.text(push.authorization))
            LabeledContent("Registration", value: Self.text(push.registration))
        }
    }

    private var devicesSection: some View {
        Section {
            switch devices.state {
            case .loading:
                ProgressView()
            case let .failed(failure):
                Text(failure.message).foregroundStyle(.secondary)
            case let .loaded(list):
                ForEach(list, id: \.deviceId) { device in
                    deviceRow(device)
                }
            }
            if let notice = devices.notice {
                Text(notice).foregroundStyle(.red)
            }
        } header: {
            Text("Signed-in devices")
        }
    }

    private func deviceRow(_ device: DeviceSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DevicesModel.label(for: device))
                Text(DevicesModel.platformName(device.platform))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.deviceId == devices.thisDeviceId {
                Text("This Mac").foregroundStyle(.secondary)
            } else {
                Button("Sign Out") {
                    Task { await devices.revoke(deviceId: device.deviceId) }
                }
                .disabled(devices.revoking != nil)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.version)
            LabeledContent("Installation id", value: container.deviceId)
                .textSelection(.enabled)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func text(_ authorization: PushAuthorization) -> String {
        switch authorization {
        case .notAsked: "Not asked yet"
        case .authorized: "Allowed"
        case .denied: "Turned off in System Settings"
        case .unavailable: "Unavailable"
        }
    }

    static func text(_ registration: PushRegistrationStatus) -> String {
        switch registration {
        case .notAttempted: "Not registered"
        case .registered: "Registered"
        case let .refused(status): "Refused by the service (\(status))"
        case .unreachable: "Could not reach the service"
        case .apnsRefused: "Apple did not issue a token for this build"
        }
    }
}
