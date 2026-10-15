import Foundation

/// Wait for work a quit owes, for at most a few seconds.
///
/// ⚠️ A RACE, NOT A CANCELLATION: awaiting a task's value is not interrupted by cancelling
/// the waiter, so the deadline resumes the caller itself and the work carries on in the
/// background for as long as the process lives. Used by the carrier hang-ups
/// (``CallStack/drainServerHangUps(within:)``) and by the token refresh
/// (``SessionModel/finishForQuit(within:)``) before the app lets the process go.
enum QuitDeadline {
    static func wait(atMost seconds: Double, for work: @escaping @Sendable () async -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = ResumeOnce(continuation)
            Task {
                await work()
                resume.fire()
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                resume.fire()
            }
        }
    }
}

/// Resumes a continuation the first time it is fired, and never again.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }
}
