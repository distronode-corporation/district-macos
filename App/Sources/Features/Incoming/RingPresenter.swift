import AppKit
import Foundation
import UserNotifications

/// How a ring is put in front of the person: what ``IncomingCallModel`` asks for at
/// `startRinging` and `stopRinging`.
///
/// ⚠️ A PROTOCOL SO THE MODEL'S TESTS RING NOTHING AND POST NOTHING.
@MainActor
protocol RingPresenting: AnyObject {
    func startRinging(workspaceId: String, callId: String)
    func stopRinging()
}

/// The ring on a Mac: the sound, the notification and the Dock. The panel is
/// ``RingPanelController``'s, which follows the model rather than this.
///
/// ⚠️ ALL OF THIS IS iOS's CALLKIT SCREEN, DONE BY HAND. A phone's system call UI rings,
/// vibrates and lights the lock screen; a Mac has no such surface for a third-party app
/// without CallKit, which this app does not use by decision (plan decision 4).
@MainActor
final class RingPresenter: RingPresenting {
    /// The system sound the ring repeats. ⚠️ A sound that ships with every Mac
    /// (`/System/Library/Sounds`), so nothing is bundled and nothing is licensed.
    static let soundName = "Submarine"

    /// The gap between rings, so it reads as a telephone ringing rather than one tone.
    static let cadenceMilliseconds = 2500

    private let center: UNUserNotificationCenter
    private var callId: String?
    private var cadence: Task<Void, Never>?
    private var attention: Int?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func startRinging(workspaceId: String, callId: String) {
        stopRinging()
        self.callId = callId
        startSound()
        attention = NSApplication.shared.requestUserAttention(.criticalRequest)
        post(workspaceId: workspaceId, callId: callId)
        removeDuplicates()
    }

    func stopRinging() {
        cadence?.cancel()
        cadence = nil
        if let attention {
            NSApplication.shared.cancelUserAttentionRequest(attention)
        }
        attention = nil
        guard let ended = callId else { return }
        callId = nil
        removeLeftovers(of: ended)
    }

    /// The call ringing now, for the app delegate's `willPresent`.
    var ringingCallId: String? {
        callId
    }

    /// An APNs alert arrived while the app runs: if it duplicates the ring, take it away.
    func removeDuplicates() {
        guard let ringing = callId else { return }
        let center = center
        Task {
            let delivered = await center.deliveredNotifications().map(Self.entry)
            let doubles = RingNotifications.duplicates(in: delivered, ringingCallId: ringing)
            guard !doubles.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: doubles)
        }
    }

    // MARK: - Pieces

    /// ⚠️ THE NOTIFICATION HAS NO SOUND OF ITS OWN: the app plays the ring while it runs,
    /// and a notification sound on top would be a second, different ring.
    ///
    /// ⛔ ITS WORDS ARE THE APNs ALERT'S (`push.call.title` and `push.call.body`), so the
    /// two notifications this Mac can show for a call read the same, and name nobody.
    private func post(workspaceId: String, callId: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "push.call.title")
        content.body = String(localized: "push.call.body")
        content.categoryIdentifier = RingNotifications.category
        content.userInfo = RingNotifications.userInfo(workspaceId: workspaceId, callId: callId)
        content.threadIdentifier = workspaceId
        let request = UNNotificationRequest(
            identifier: RingNotifications.identifier(callId: callId),
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }

    private func removeLeftovers(of callId: String) {
        let center = center
        Task {
            let delivered = await center.deliveredNotifications().map(Self.entry)
            let leftovers = RingNotifications.leftovers(in: delivered, callId: callId)
            center.removeDeliveredNotifications(withIdentifiers: leftovers)
            center.removePendingNotificationRequests(withIdentifiers: [RingNotifications.identifier(callId: callId)])
        }
    }

    private func startSound() {
        let name = Self.soundName
        let gap = Self.cadenceMilliseconds
        cadence = Task { @MainActor in
            while !Task.isCancelled {
                NSSound(named: NSSound.Name(name))?.play()
                try? await Task.sleep(for: .milliseconds(gap))
            }
        }
    }

    private typealias Delivered = (identifier: String, userInfo: [AnyHashable: Any])

    private nonisolated static func entry(_ notification: UNNotification) -> Delivered {
        (notification.request.identifier, notification.request.content.userInfo)
    }
}
