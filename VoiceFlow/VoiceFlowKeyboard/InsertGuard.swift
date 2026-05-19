//
//  InsertGuard.swift
//  VoiceFlowKeyboard
//

import UIKit
import VoiceFlowShared

/// Pre-record checks that block dictation when the current field does not support it.
struct InsertGuard {
    /// Returns a reason if the field should block dictation, or nil if dictation is allowed.
    static func check(proxy: UITextDocumentProxy) -> InsertUnavailableReason? {
        switch proxy.keyboardType {
        case .phonePad, .namePhonePad, .numberPad, .decimalPad:
            return .unsupportedKeyboardType
        default:
            return nil
        }
    }
}
