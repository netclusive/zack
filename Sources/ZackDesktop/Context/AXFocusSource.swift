import AppKit
import ApplicationServices
import Dispatch
import Foundation

#if DEBUG
    /// Lines for the debug window; contains no field content except the last 40 characters before the cursor.
    public struct FocusDiagnostics: Sendable {
        public var lines: [String]

        public init(lines: [String]) {
            self.lines = lines
        }
    }
#endif

/// Reads the focused field through Accessibility. Every call runs on one private serial queue, never on the main
/// thread, and every element gets a messaging timeout so a hanging app cannot block a dictation.
public final class AXFocusSource: FocusSource {
    public static let timeout: Float = 0.1
    public static let valueLimit = 100_000

    private let queue = DispatchQueue(label: "com.netclusive.zack.focus")

    public init() {}

    public func read(text: Bool) async -> FocusSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.readSnapshot(text: text)) }
        }
    }

    public func text(in range: TextRange, of element: FocusElement) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard AXIsProcessTrusted(), let current = Self.current(), Self.matches(current, element) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.string(in: range, of: current.element))
            }
        }
    }

    public func select(_ range: TextRange, in element: FocusElement) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard AXIsProcessTrusted(), let current = Self.current(), Self.matches(current, element) else {
                    continuation.resume(returning: false)
                    return
                }
                var cfRange = CFRange(location: range.location, length: range.length)
                guard let value = AXValueCreate(.cfRange, &cfRange),
                    AXUIElementSetAttributeValue(current.element, kAXSelectedTextRangeAttribute as CFString, value)
                        == .success
                else {
                    continuation.resume(returning: false)
                    return
                }
                guard Self.selection(of: current.element) == range else {
                    // Set, but read back otherwise (or not yet, as in Electron apps): best effort, the caret goes
                    // behind the text, so a selection that shows up after all is not replaced by the next key.
                    Self.placeCaret(after: range, in: current.element)
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: true)
            }
        }
    }

    /// Sets an empty selection at the end of `range`; the result is not checked.
    private static func placeCaret(after range: TextRange, in element: AXUIElement) {
        guard range.length <= Int.max - range.location else { return }
        var caret = CFRange(location: range.location + range.length, length: 0)
        guard let value = AXValueCreate(.cfRange, &caret) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    #if DEBUG
        /// Reads the focus once and reports what worked, for hand checks in the debug menu. Only the last 40
        /// characters of text appear.
        public func diagnose() async -> FocusDiagnostics {
            let front = await Self.frontmost()
            return await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: Self.diagnoseNow(front: front)) }
            }
        }

        private struct Frontmost: Sendable {
            let pid: pid_t?
            let bundleID: String?
        }

        @MainActor
        private static func frontmost() -> Frontmost {
            let app = NSWorkspace.shared.frontmostApplication
            return Frontmost(pid: app?.processIdentifier, bundleID: app?.bundleIdentifier)
        }
    #endif

    // MARK: - Queue-only helpers

    private struct Focus {
        let element: AXUIElement
        let pid: Int32
    }

    private static func readSnapshot(text: Bool) -> FocusSnapshot {
        guard AXIsProcessTrusted(), let focus = current() else { return .unknown }
        let element = FocusElement(pid: focus.pid, reference: focus.element)
        // Fail closed: if the field type cannot be read, report nothing rather than risk reading a password field.
        guard case .value(let sub) = readSubrole(of: focus.element) else { return .unknown }
        if sub == kAXSecureTextFieldSubrole as String {
            return FocusSnapshot(element: element, isSecure: true)
        }
        let selection = selection(of: focus.element)
        var before: String?
        if text, let selection {
            before = string(in: ContextResolver.readRange(before: selection.location), of: focus.element)
                .map(ContextResolver.trim)
        }
        return FocusSnapshot(element: element, isSecure: false, selection: selection, textBeforeCursor: before)
    }

    /// The focused element of the focused app, each with the messaging timeout set.
    private static func current() -> Focus? {
        let system = AXUIElementCreateSystemWide()
        // Per the SDK header this timeout applies to the whole process, not only to the system-wide element.
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let app = axElement(attribute(system, kAXFocusedApplicationAttribute)) else { return nil }
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let element = axElement(attribute(app, kAXFocusedUIElementAttribute)) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return Focus(element: element, pid: pid)
    }

    private static func matches(_ focus: Focus, _ element: FocusElement) -> Bool {
        focus.pid == element.pid && CFEqual(focus.element, element.reference)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private enum SubroleRead {
        case value(String?)
        case failed(AXError)
    }

    /// `.noValue` and `.attributeUnsupported` mean "no subrole"; any other error (e.g. a timeout) is undecided.
    private static func readSubrole(of element: AXUIElement) -> SubroleRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        switch error {
        case .success: return .value(value as? String)
        case .noValue, .attributeUnsupported: return .value(nil)
        default: return .failed(error)
        }
    }

    private static func selection(of element: AXUIElement) -> TextRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return selectionRange(range)
    }

    /// A selection as reported; nil for negative values, for `NSNotFound`, which some apps send for "no selection",
    /// and for an end beyond `Int.max`.
    static func selectionRange(_ range: CFRange) -> TextRange? {
        guard range.location >= 0, range.length >= 0, range.location != NSNotFound,
            range.length <= Int.max - range.location
        else { return nil }
        return TextRange(location: range.location, length: range.length)
    }

    /// Text of `range`: the range query first, then the whole value for fields of moderate size.
    private static func string(in range: TextRange, of element: AXUIElement) -> String? {
        stringForRange(range, of: element) ?? valueSlice(range, of: element)
    }

    private static func stringForRange(_ range: TextRange, of element: AXUIElement) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var result: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result) == .success
        else { return nil }
        return result as? String
    }

    private static func valueSlice(_ range: TextRange, of element: AXUIElement) -> String? {
        guard let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue,
            count <= valueLimit,
            let value = attribute(element, kAXValueAttribute) as? String
        else { return nil }
        return utf16Slice(value, range)
    }

    /// The part of `string` inside `range` (UTF-16 units); `nil` if the range reaches beyond the string.
    static func utf16Slice(_ string: String, _ range: TextRange) -> String? {
        let units = string.utf16
        // Compared without adding: location and length may come straight from an app, up to `Int.max`.
        guard range.location >= 0, range.length >= 0, range.location <= units.count,
            range.length <= units.count - range.location
        else { return nil }
        let from = units.index(units.startIndex, offsetBy: range.location)
        let to = units.index(from, offsetBy: range.length)
        return String(decoding: Array(units[from..<to]), as: UTF16.self)
    }

    #if DEBUG
        /// One attribute read that keeps the raw `AXError` instead of swallowing it.
        private static func probe(_ element: AXUIElement, _ name: String) -> (element: AXUIElement?, status: String) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            guard error == .success else { return (nil, "Fehler \(error.rawValue)") }
            guard let found = axElement(value) else { return (nil, "Fehler Typ") }
            return (found, "ok")
        }

        private static func milliseconds(since start: UInt64) -> UInt64 {
            (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }

        /// Weg A: the same three steps as `current()`, with each error recorded.
        private static func probeSystemWide() -> String {
            let start = DispatchTime.now().uptimeNanoseconds
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, timeout)
            var appStatus = "nicht geprüft"
            var elementStatus = "nicht geprüft"
            var pidStatus = "nicht geprüft"
            let app = probe(system, kAXFocusedApplicationAttribute)
            appStatus = app.status
            if let appElement = app.element {
                AXUIElementSetMessagingTimeout(appElement, timeout)
                let focused = probe(appElement, kAXFocusedUIElementAttribute)
                elementStatus = focused.status
                if let focusedElement = focused.element {
                    AXUIElementSetMessagingTimeout(focusedElement, timeout)
                    var pid: pid_t = 0
                    let error = AXUIElementGetPid(focusedElement, &pid)
                    pidStatus = error == .success ? "ok" : "Fehler \(error.rawValue)"
                }
            }
            return "Weg A systemweit: App \(appStatus), Element \(elementStatus), PID \(pidStatus) "
                + "(\(milliseconds(since: start)) ms)"
        }

        /// Weg B: per-app element from the NSWorkspace pid, like `ScreenLocator`. No timeout is set on this element,
        /// but the process-wide timeout set by Weg A may still apply.
        private static func probeWorkspace(_ front: Frontmost) -> String {
            let start = DispatchTime.now().uptimeNanoseconds
            let head = "Weg B über NSWorkspace (PID \(front.pid.map { String($0) } ?? "–"), \(front.bundleID ?? "–")): "
            guard let pid = front.pid else {
                return head + "Fenster nicht geprüft, Element nicht geprüft (\(milliseconds(since: start)) ms)"
            }
            let app = AXUIElementCreateApplication(pid)
            let window = probe(app, kAXFocusedWindowAttribute)
            let element = probe(app, kAXFocusedUIElementAttribute)
            return head + "Fenster \(window.status), Element \(element.status) (\(milliseconds(since: start)) ms)"
        }

        /// Weg C: the focused element straight from the system-wide element.
        private static func probeSystemDirect() -> String {
            let start = DispatchTime.now().uptimeNanoseconds
            let element = probe(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
            return "Weg C systemweit direkt: Element \(element.status) (\(milliseconds(since: start)) ms)"
        }

        private static func diagnoseNow(front: Frontmost) -> FocusDiagnostics {
            let zackFront = front.bundleID != nil && front.bundleID == Bundle.main.bundleIdentifier
            let header = [
                probeSystemWide(),
                probeWorkspace(front),
                probeSystemDirect(),
                "Zack im Vordergrund laut NSWorkspace: " + (zackFront ? "ja" : "nein"),
            ]
            return FocusDiagnostics(lines: header + diagnoseFocus().lines)
        }

        private static func diagnoseFocus() -> FocusDiagnostics {
            let begin = DispatchTime.now().uptimeNanoseconds
            var durations: [String] = []
            func measured<T>(_ label: String, _ body: () -> T) -> T {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = body()
                durations.append("\(label) \((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) ms")
                return result
            }
            func yesNo(_ value: Bool) -> String { value ? "ja" : "nein" }
            func total() -> String { "Gesamt: \((DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000) ms" }

            guard AXIsProcessTrusted() else {
                return FocusDiagnostics(lines: ["Bedienungshilfen: nicht erlaubt"])
            }
            guard let focus = measured("Fokus", { current() }) else {
                return FocusDiagnostics(lines: ["Kein fokussiertes Element gefunden", total()])
            }
            let element = focus.element
            let role = measured("Rolle") { attribute(element, kAXRoleAttribute) as? String }
            var lines = ["Rolle: \(role ?? "–")"]
            let subroleRead = measured("Subrolle") { readSubrole(of: element) }
            let sub: String?
            switch subroleRead {
            case .value(let value): sub = value
            case .failed(let error):
                lines.append("Subrolle: Fehler \(error.rawValue)")
                lines.append(total())
                return FocusDiagnostics(lines: lines)
            }
            let secure = sub == kAXSecureTextFieldSubrole as String
            lines.append("Subrolle: \(sub ?? "–")")
            lines.append("Passwortfeld: \(yesNo(secure))")
            if secure {
                lines.append("Passwortfeld, nichts weiter gelesen")
                lines.append("Dauer je Abfrage: " + durations.joined(separator: ", "))
                lines.append(total())
                return FocusDiagnostics(lines: lines)
            }

            let selection = measured("Auswahl") { selection(of: element) }
            lines.append("Auswahl: " + (selection.map { "\($0.location), \($0.length)" } ?? "–"))

            var viaRange = "nicht geprüft"
            var viaValue = "nicht geprüft"
            var before: String?
            if let selection {
                let range = ContextResolver.readRange(before: selection.location)
                let direct = measured("AXStringForRange") { stringForRange(range, of: element) }
                viaRange = yesNo(direct != nil)
                before = direct
                if direct == nil {
                    let fallback = measured("AXValue") { valueSlice(range, of: element) }
                    viaValue = yesNo(fallback != nil)
                    before = fallback
                }
            }
            lines.append("AXStringForRange: \(viaRange)")
            lines.append("Rückfall AXValue: \(viaValue)")

            let settable = measured("Setzbar") { () -> Bool in
                var flag = DarwinBoolean(false)
                let result = AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &flag)
                return result == .success && flag.boolValue
            }
            lines.append("Auswahl setzbar: \(yesNo(settable))")

            let again = measured("Fokus erneut") { current() }
            lines.append(
                "Element zweimal gelesen gleich: \(yesNo(again.map { CFEqual($0.element, element) } ?? false))")

            let tail = before.map { String(ContextResolver.trim($0).suffix(40)) }
            let shown = tail?.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "⏎")
            lines.append("Text vor dem Cursor (letzte 40): " + (shown.map { "„\($0)“" } ?? "–"))
            lines.append("Dauer je Abfrage: " + durations.joined(separator: ", "))
            lines.append(total())
            return FocusDiagnostics(lines: lines)
        }
    #endif
}
