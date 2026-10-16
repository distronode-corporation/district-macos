import AppKit
import ApplicationServices
import XCTest

/// The app's Accessibility tree read the way an assistive app reads it: the C
/// Accessibility API (`AXUIElement`), from this test runner's process, against the app's.
///
/// ⛔ NOT XCUITest's QUERIES, AND NOT THE APP'S OWN `NSAccessibility` OBJECTS. XCUITest
/// clicks with mouse events, and a SwiftUI view builds its accessibility tree only for a
/// client in another process (an in-process walk of a hosting view finds one empty
/// `AXGroup`, even for a stock button). This is what VoiceOver and an automation script
/// do: `AXRole`, the label, `AXActionNames`, and `AXPress` performed.
enum AXProbe {
    /// The newest running copy of the app under test.
    static func pid() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.distronode.district") && !$0.isTerminated }
            .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }?
            .processIdentifier
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    /// Every element under the app's windows, breadth first.
    static func elements(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var queue = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var found: [AXUIElement] = []
        while !queue.isEmpty, found.count < 5000 {
            let element = queue.removeFirst()
            found.append(element)
            queue += attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return found
    }

    /// The AXButtons whose title or description is `label`.
    static func buttons(pid: pid_t, labelled label: String) -> [AXUIElement] {
        elements(pid: pid).filter {
            string($0, kAXRoleAttribute) == kAXButtonRole
                && (string($0, kAXTitleAttribute) == label || string($0, kAXDescriptionAttribute) == label)
        }
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    /// Every element's role and label, for a failure message.
    static func report(pid: pid_t) -> String {
        elements(pid: pid).map {
            "\(string($0, kAXRoleAttribute)) '\(string($0, kAXTitleAttribute))|\(string($0, kAXDescriptionAttribute))'"
        }.joined(separator: " ; ")
    }

    /// Wait until an AXButton labelled `label` exists, as an assistive app would find it.
    static func waitForButton(_ label: String, timeout: TimeInterval) -> (pid_t, AXUIElement)? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let pid = pid(), let button = buttons(pid: pid, labelled: label).first {
                return (pid, button)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return nil
    }
}
