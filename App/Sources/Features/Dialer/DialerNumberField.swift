import AppKit
import SwiftUI

/// The dialler's number field: an `NSTextField` that formats the number as it is typed.
///
/// ⛔ AppKit RATHER THAN A SwiftUI `TextField`, FOR THE REASON district-ios's
/// `DialerNumberField` gives. There, with the formatted number written back through SwiftUI
/// state, typing `4165550199` at speed left `(416) 5`: the new text reaches the platform
/// field after the keystroke has been handled, and a keystroke that arrives in between is
/// overwritten. A dropped middle digit can leave a valid number that is not the one typed.
/// Here each edit is formatted inside `controlTextDidChange(_:)`, synchronously, on the
/// field editor's own change, so there is no window for a keystroke to fall into. Typing
/// and paste both arrive there.
///
/// ⚠️ THE CARET GOES TO THE END AFTER EACH EDIT. Formatting moves characters around, and a
/// caret kept at its old offset would land inside a group; the end is where the next digit
/// belongs in the overwhelming case.
///
/// ⛔ LEAVING THE FIELD AND RETURN ARE REPORTED (`onCommit`), because a wrong-length number
/// is said only then (see ``DialerModel/entryProblem(_:lengthChecked:)``). ⚠️ Return does not
/// dial: Call is its own button, and a stray Return must not spend money.
struct DialerNumberField: NSViewRepresentable {
    let placeholder: String
    let text: String
    let isEnabled: Bool
    let ink: Color
    let placeholderInk: Color
    /// Apply one edit: the field's whole proposed text in, the text it should show out.
    let onEdit: (String) -> String
    /// The operator stopped: the field lost focus, or Return was pressed in it.
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        // ⚠️ NO BEZEL AND NO FILL OF ITS OWN: ``View/districtField()`` draws the card ground and
        // the 1px edge around it, as on every other field in the app.
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        // ⚠️ THE SIZE OF ``DistrictType/bodySmall`` (14 pt).
        field.font = .systemFont(ofSize: 14)
        field.setAccessibilityIdentifier(A11yID.Dialer.entry)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onEdit = onEdit
        context.coordinator.onCommit = onCommit
        // ⚠️ ONLY WHEN IT DIFFERS: a call-back row or a country pick changes the entry from
        // outside. While typing, the delegate has already written this value.
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = isEnabled
        field.textColor = NSColor(ink)
        field.setAccessibilityLabel(placeholder)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor(placeholderInk), .font: NSFont.systemFont(ofSize: 14)]
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onEdit: (String) -> String
        var onCommit: () -> Void

        init(onEdit: @escaping (String) -> String, onCommit: @escaping () -> Void) {
            self.onEdit = onEdit
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let shown = onEdit(field.stringValue)
            if field.stringValue != shown {
                field.stringValue = shown
            }
            field.currentEditor()?.selectedRange = NSRange(location: (shown as NSString).length, length: 0)
        }

        func controlTextDidEndEditing(_: Notification) {
            onCommit()
        }

        /// ⚠️ RETURN IS TAKEN HERE so it says the length without ending the edit: the caret
        /// stays in the field for the correction.
        func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            onCommit()
            return true
        }
    }
}
