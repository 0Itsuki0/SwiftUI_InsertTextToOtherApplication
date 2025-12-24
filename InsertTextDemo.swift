
import SwiftUI
import Carbon

struct InsertTextDemo: View {
    private let textToInsert = "This is a test"
    var body: some View {
        VStack {
            Text("Shift + Command + Space to insert `\(textToInsert)`")
                .font(.headline)
        }
        .onAppear {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
                if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] {
                    do {
                        try TextInserter.insertText(textToInsert)
                    } catch (let error) {
                        print(error)
                        try? TextInserter.simulateCopyPaste(textToInsert)
                    }
                }
            })
        }
    }
}


private enum AccessibilityError: String, Error, LocalizedError {
    case permissionNotGranted
}

enum InsertTextError: String, Error, LocalizedError {
    case unsettableElement
    case unsettableApp
    case failToCopyPaste

    // MARK: - AXError mapped
    // AXError.failure
    case generalFailure
    case illegalArgument
    case invalidUIElement
    case invalidUIElementObserver
    case cannotComplete
    case attributeUnsupported
    case actionUnsupported
    case notificationUnsupported
    case notImplemented
    case notificationAlreadyRegistered
    case notificationNotRegistered
    case apiDisabled
    case noValue
    case parameterizedAttributeUnsupported
    case notEnoughPrecision

    var recoverySuggestion: String? {
        switch self {
        default:
            "Transcription Copy to the clipboard and Paste command is simulated."
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsettableElement:
            "No Focused Input Found."
        case .unsettableApp:
            "Target Application does not support inserting text through Accessibility API."
        case .failToCopyPaste:
            "Fail to simulate copy and paste."
        default:
            "Something went wrong with Accessibility API: \(self.rawValue)"
        }
    }

    init?(_ axError: AXError) {
        switch axError {
        case .success:
            return nil
        case .failure:
            self = .generalFailure
        case .illegalArgument:
            self = .illegalArgument
        case .invalidUIElement:
            self = .invalidUIElement
        case .invalidUIElementObserver:
            self = .invalidUIElementObserver
        case .cannotComplete:
            self = .cannotComplete
        case .attributeUnsupported:
            self = .attributeUnsupported
        case .actionUnsupported:
            self = .actionUnsupported
        case .notificationUnsupported:
            self = .notificationUnsupported
        case .notImplemented:
            self = .notImplemented
        case .notificationAlreadyRegistered:
            self = .notificationAlreadyRegistered
        case .notificationNotRegistered:
            self = .notificationNotRegistered
        case .apiDisabled:
            self = .apiDisabled
        case .noValue:
            self = .noValue
        case .parameterizedAttributeUnsupported:
            self = .parameterizedAttributeUnsupported
        case .notEnoughPrecision:
            self = .notEnoughPrecision
        @unknown default:
            self = .generalFailure
        }
    }

}


nonisolated class TextInserter {
    // NOTE:
    // kAXComboBoxRole's value COULD be set using the kAXValueAttribute.
    // However, there are couple problems with setting this property.
    // 1. It will REPLACE the value with what we set. We could get the value and append the new one to it, but that will ignore the cursor's position. This is different from a text element where when we set the kAXSelectedTextAttribute, it will automatically insert the text based on the cursor's position
    // 2. It is not guaranteed that a combo box is actually a text entry.
    private static let textElementRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole,
    ]

    private init() {}

    static func insertText(_ text: String) throws {
        try AccessibilityManager.checkAccessibilityPermission()

        let focusedAXElement = try self.findFocusedElement()

        let role = try getElementRole(focusedAXElement)

        if !textElementRoles.contains(role) {
            throw InsertTextError.unsettableElement
        }

        // setting kAXSelectedTextAttribute will insert the text based on the cursor's position
        // only work for kAXTextFieldRole, kAXTextAreaRole?
        // even we cannot insert into it, for example, if the current focus is combo box, we won't get an error either. That's why we are checking to see if the value actually changed.

        let currentValue = try self.getCurrentValue(focusedAXElement)

        let updateTextAttributeResult = AXUIElementSetAttributeValue(
            focusedAXElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        try self.checkAXError(updateTextAttributeResult)

        let newValue = try self.getCurrentValue(focusedAXElement)
        // for applications such as Google Doc or VSCode,
        // the role is TextArea, the kAXSelectedTextAttribute is Settable, we get a success when calling AXUIElementSetAttributeValue
        // however, the actual value will not be updated, possibly due to those system handle text in a specific way, for example, with some kinds of format.
        if currentValue == newValue {
            throw InsertTextError.unsettableApp
        }

    }

    static private func findFocusedElement() throws -> AXUIElement {

        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        try checkAXError(error)

        guard let focusedAXElement = focusedElement as! AXUIElement? else {
            throw InsertTextError.generalFailure
        }

        return focusedAXElement

    }

    static private func getCurrentValue(_ element: AXUIElement) throws -> String
    {
        return try self.getStringValueForAttribute(
            element,
            attribute: kAXValueAttribute
        )
    }

    static private func getStringValueForAttribute(
        _ element: AXUIElement,
        attribute: String
    ) throws -> String {
        var value: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        try checkAXError(error)

        guard let valueString = value as? String else {
            throw InsertTextError.generalFailure
        }

        return valueString
    }

    static private func getElementRole(_ element: AXUIElement) throws -> String
    {
        var role: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &role
        )

        try checkAXError(error)

        guard let roleString = role as? String else {
            throw InsertTextError.generalFailure
        }

        print("Focused element role: \(roleString)")

        return roleString

    }

    static private func checkAXError(_ error: AXError) throws {
        if let error = InsertTextError(error) {
            throw error
        }
    }

    static func simulateCopyPaste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let result = pasteboard.setString(text, forType: .string)
        if !result {
            throw InsertTextError.failToCopyPaste
        }
        self.simulateKeyDown(key: CGKeyCode(kVK_ANSI_V), with: .maskCommand)
    }

    static private func simulateKeyDown(key: CGKeyCode, with flags: CGEventFlags) {
        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: key,
            keyDown: true
        )
        event?.flags = flags
        event?.post(tap: CGEventTapLocation.cghidEventTap)
    }

}



nonisolated final class AccessibilityManager {
    var onPermissionChange: (() -> Void)?

    static func checkAccessibilityPermission() throws {
        try self.requestPermissionHelper(displayPrompt: false)
    }

    static func requestAccessibilityPermission() {
        // not throwing here because this is intended to be called to prompt for permission instead of showing error
        try? self.requestPermissionHelper(displayPrompt: true)
    }

    private static func requestPermissionHelper(displayPrompt: Bool) throws {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: displayPrompt
        ]

        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            throw AccessibilityError.accessibilityPermissionNotGranted
        }
    }

    private var cancellable: AnyCancellable?

    init() {
        self.cancellable = NSWorkspace
            .accessibilityDisplayOptionsDidChangeNotification.publisher.receive(
                on: DispatchQueue.main
            ).sink { _ in
                self.onPermissionChange?()
            }
    }

    deinit {
        self.cancellable?.cancel()
        self.cancellable = nil
    }
}
