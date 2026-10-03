import DistrictCall
import Foundation

/// The two background tasks one outbound call owns.
///
/// ⛔ SPLIT OUT OF `DialerModel.swift` BECAUSE OF THE 500-LINE `file_length`
/// CEILING, WHICH `swiftlint --strict` PROMOTES TO AN ERROR, AND THAT IS THE WHOLE
/// REASON. It is the same call `DialerCopy.swift` and `DialerEntry.swift` make
/// about the same type; nothing here is a separate concern from the model.
///
/// ⚠️ THE PRICE IS FOUR MEMBERS THAT WOULD OTHERWISE BE `private` AND ARE
/// MODULE-VISIBLE: `calls`, `engineTask`, `tickTask` and `apply(_:)`. (iOS also widens
/// a start watchdog; a Mac has no system start to wait for, so it has none.) Swift's `private` is file-scoped, so an
/// extension in
/// another file cannot reach one. ⛔ `refusal` DELIBERATELY DOES NOT WIDEN, which is
/// why `abandonStart(uuid:)` stays in the model file: it is the one member here
/// that WRITES, and `private(set)` is what stops a view assigning a refusal the
/// keypad never earned. Widen nothing else without the same test.
extension DialerModel {
    /// ⛔ THE ENGINE STREAM IS READ EXACTLY ONCE, HERE. `AsyncStream` delivers each
    /// element to a SINGLE consumer, so a second `for await` would silently split the
    /// events between two readers rather than mirroring them, half the reducer's
    /// input, chosen at random.
    ///
    /// ⚠️ THE STREAM IS NEVER FINISHED BY THE ENGINE (``LiveKitCallEngine`` says so:
    /// the SDK reports its disconnect reason AFTER `disconnect()`), so the loop ends by
    /// CANCELLATION from ``release()`` and by the continuation dying with the engine.
    ///
    /// ⚠️ `[weak self]` BECAUSE THE CLAIM IS THE ANCHOR. A strong capture here would be
    /// a second lifetime rule that could disagree with it.
    ///
    /// ⚠️ `await` ON ``CallStack/beginCall()`` BECAUSE IT TAKES THE AUDIO OFF A LIVE
    /// ROOM FIRST. On this path that is always a no-op, ``placeCall()`` refuses a dial
    /// while a room is live, but the seam is one function for both directions and the
    /// inbound answer genuinely waits on it.
    func startEngine() async {
        let events = await calls.beginCall()
        engineTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                await apply(.engine(event))
            }
        }
    }

    /// One second of an answered call.
    ///
    /// ⚠️ A CLOCK OUTSIDE THE REDUCER, WHICH IS THE WHOLE REASON
    /// ``SoftphoneEvent/tick`` IS AN EVENT. The reducer counts nothing while ringing,
    /// so this may be started at the answer and left to run.
    func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await apply(.tick)
            }
        }
    }
}
