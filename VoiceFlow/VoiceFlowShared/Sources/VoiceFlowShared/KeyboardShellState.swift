import Foundation

public enum KeyboardShellState: Equatable, Sendable {
    case compact(hasPendingInsert: Bool)
    case recording(elapsedSeconds: Int)
    case transcribing(elapsedSeconds: Int)
    case reviewing(preview: String, elapsedSeconds: Int)
    case pending(preview: String)
    case insertUnavailable(reason: InsertUnavailableReason)
}

public struct KeyboardShellViewModel: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let preview: String?
    public let primaryActionTitle: String
    public let secondaryActionTitle: String?
    public let showsLevelMeter: Bool
    public let timerText: String?
    public let primaryActionEnabled: Bool

    public init(state: KeyboardShellState) {
        switch state {
        case .compact(let hasPendingInsert):
            title = "VoiceFlow"
            detail = hasPendingInsert ? "Pending text is ready." : "Ready to dictate."
            preview = nil
            primaryActionTitle = "Dictate"
            secondaryActionTitle = hasPendingInsert ? "Review Pending" : nil
            showsLevelMeter = false
            timerText = nil
            primaryActionEnabled = true

        case .recording(let elapsedSeconds):
            title = "Recording"
            detail = "Listening now."
            preview = nil
            primaryActionTitle = "Stop"
            secondaryActionTitle = "Cancel"
            showsLevelMeter = true
            timerText = Self.format(seconds: elapsedSeconds)
            primaryActionEnabled = true

        case .transcribing(let elapsedSeconds):
            title = "Transcribing"
            detail = "Preparing text."
            preview = nil
            primaryActionTitle = "Review"
            secondaryActionTitle = "Cancel"
            showsLevelMeter = true
            timerText = Self.format(seconds: elapsedSeconds)
            primaryActionEnabled = true

        case .reviewing(let text, let elapsedSeconds):
            title = "Review"
            detail = "Check the text before insert."
            preview = Self.preview(text)
            primaryActionTitle = "Use Text"
            secondaryActionTitle = "Cancel"
            showsLevelMeter = true
            timerText = Self.format(seconds: elapsedSeconds)
            primaryActionEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .pending(let text):
            title = "Pending"
            detail = "Text is ready to insert."
            preview = Self.preview(text)
            primaryActionTitle = "Insert"
            secondaryActionTitle = "Discard"
            showsLevelMeter = false
            timerText = nil
            primaryActionEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .insertUnavailable(let reason):
            title = "Insert Unavailable"
            detail = reason.keyboardShellMessage
            preview = nil
            primaryActionTitle = "Copy"
            secondaryActionTitle = "Dismiss"
            showsLevelMeter = false
            timerText = nil
            primaryActionEnabled = reason.offersClipboardFallback
        }
    }

    private static func preview(_ text: String) -> String {
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard compact.count > 160 else {
            return compact
        }

        let endIndex = compact.index(compact.startIndex, offsetBy: 160)
        return String(compact[..<endIndex]) + "..."
    }

    private static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}

public extension InsertUnavailableReason {
    var keyboardShellMessage: String {
        switch self {
        case .noPendingText:
            return "No pending text is available."
        case .secureField:
            return "This field does not allow keyboard insertion."
        case .unsupportedKeyboardType:
            return "This field uses a keyboard type VoiceFlow cannot insert into."
        case .appDisallowsKeyboard:
            return "This app does not allow third-party keyboards here."
        case .sharedStoreUnavailable:
            return "VoiceFlow cannot reach its shared store."
        case .openAccessRequired:
            return "Full Access is required for in-keyboard dictation."
        case .unknown:
            return "VoiceFlow cannot insert in this field."
        }
    }

    var offersClipboardFallback: Bool {
        switch self {
        case .secureField, .appDisallowsKeyboard, .sharedStoreUnavailable, .unknown:
            return true
        case .noPendingText, .unsupportedKeyboardType, .openAccessRequired:
            return false
        }
    }
}
