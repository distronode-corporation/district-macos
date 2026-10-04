import DistrictData
import DistrictModel
import Foundation
import Observation

/// The booking assistant: one op behind one Save.
///
/// ⛔ NOTHING IS SENT UNLESS SOMETHING CHANGED, WHICH IS THE WEB TAB'S OWN
/// BEHAVIOUR AND NOT AN OPTIMISATION. The write counts against the workspace's
/// 120-an-hour budget, and `settings.llm.patch` with neither field is a VALID
/// no-op, the schema marks both optional, so the server would not object to a
/// wasted write. Deciding not to send is the only place that can be decided.
///
/// ⛔ AND THE ASSISTANT SCHEMA IS `z.strictObject`. Anything else in the body,
/// `stt_api_key` above all, is a **400 naming the field**, which is the intended
/// behaviour: silently accepting a credential a customer believes they set is the
/// worse of the two failures. That is why there is no key field on this form and
/// must not be one.
@MainActor
@Observable
final class SchedulingAutomationModel {
    private(set) var state: SchedulingWriteState = .idle
    private(set) var llm: SchedulingLLMSettings

    private(set) var assistantEnabled: Bool
    private(set) var instructions: String
    private(set) var rejected: String?

    private let admin: SchedulingAdminRepository
    private let workspaceId: String
    private let onSaved: () -> Void

    init(
        admin: SchedulingAdminRepository,
        workspaceId: String,
        llm: SchedulingLLMSettings,
        onSaved: @escaping () -> Void
    ) {
        self.admin = admin
        self.workspaceId = workspaceId
        self.llm = llm
        self.onSaved = onSaved
        assistantEnabled = llm.enabled
        instructions = llm.extraInstructions
    }

    var busy: Bool {
        state.isWorking
    }

    var isDirty: Bool {
        llmChanged
    }

    func editAssistant(_ value: Bool) {
        assistantEnabled = value
        clearRejection()
    }

    func editInstructions(_ value: String) {
        instructions = value
        clearRejection()
    }

    /// ⛔ ENFORCED HERE THOUGH THE WEB ONLY STATES IT. `settings.llm.patch` caps
    /// `extra_instructions` at 4000 server-side, and the refusal arrives as
    /// ``SchedulingAdminError/invalidParams`` carrying a field NAME and no message
    /// , nothing an operator can act on. The web lets zod refuse it; on a phone
    /// that is a dead end.
    var validationFailure: String? {
        instructions.count > SchedulingSettingsWriteCopy.assistantInstructionsLimit
            ? SchedulingSettingsWriteCopy.assistantInstructionsTooLong
            : nil
    }

    /// ⚠️ THE SAVED VALUE IS ADOPTED FROM THE RESPONSE, so the model holds exactly
    /// what the server holds rather than what was typed.
    func save() async {
        guard !busy, isDirty else { return }
        if let failure = validationFailure {
            rejected = failure
            return
        }
        state = .working
        do {
            llm = try await admin.updateLLMSettings(
                workspaceId: workspaceId,
                enabled: assistantEnabled,
                extraInstructions: instructions
            )
            assistantEnabled = llm.enabled
            instructions = llm.extraInstructions
            state = .done(SchedulingSettingsWriteCopy.automationDone)
            onSaved()
        } catch {
            state = .failed(SchedulingFailureCopy.text(forAny: error))
        }
    }

    /// ⚠️ `""` CLEARS THE INSTRUCTIONS AND nil LEAVES THEM ALONE, and this form
    /// always has a string, so an emptied box really does clear them, which is
    /// what an operator who emptied it meant.
    private var llmChanged: Bool {
        assistantEnabled != llm.enabled || instructions != llm.extraInstructions
    }

    private func clearRejection() {
        rejected = nil
        if case .failed = state {
            state = .idle
        }
    }
}
