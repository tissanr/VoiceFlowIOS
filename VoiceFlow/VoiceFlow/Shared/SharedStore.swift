//
//  SharedStore.swift
//  VoiceFlow
//
//  Centralized store for communication between the containing app and the keyboard extension.
//

import Foundation

public final class SharedStore {
    public static let shared = SharedStore()
    
    private let groupID = "group.com.voiceflow.shared"
    private let defaults: UserDefaults?
    
    private enum Keys {
        static let pendingInsert = "vf_pending_insert"
        static let keyboardState = "vf_keyboard_state"
        static let lastUpdated = "vf_last_updated"
    }
    
    private init() {
        self.defaults = UserDefaults(suiteName: groupID)
        if self.defaults == nil {
            print("⚠️ SharedStore: Failed to initialize UserDefaults for group: \(groupID). Check App Group entitlements.")
        }
    }
    
    // MARK: - Pending Insert
    
    public var pendingInsert: PendingInsert? {
        get {
            guard let data = defaults?.data(forKey: Keys.pendingInsert) else { return nil }
            let insert = try? JSONDecoder().decode(PendingInsert.self, from: data)
            
            // Auto-clear if expired
            if let insert = insert, insert.isExpired {
                clearPendingInsert()
                return nil
            }
            return insert
        }
        set {
            if let newValue = newValue {
                let data = try? JSONEncoder().encode(newValue)
                defaults?.set(data, forKey: Keys.pendingInsert)
                updateTimestamp()
            } else {
                clearPendingInsert()
            }
        }
    }
    
    public func clearPendingInsert() {
        defaults?.removeObject(forKey: Keys.pendingInsert)
        updateTimestamp()
    }
    
    // MARK: - Keyboard State
    
    public var keyboardState: KeyboardState {
        get {
            guard let data = defaults?.data(forKey: Keys.keyboardState) else {
                return defaults == nil ? .noSharedAccess : .ready
            }
            return (try? JSONDecoder().decode(KeyboardState.self, from: data)) ?? .ready
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults?.set(data, forKey: Keys.keyboardState)
            updateTimestamp()
        }
    }
    
    // MARK: - Utilities
    
    public var lastUpdated: Date? {
        defaults?.object(forKey: Keys.lastUpdated) as? Date
    }
    
    private func updateTimestamp() {
        defaults?.set(Date(), forKey: Keys.lastUpdated)
    }
    
    /// Verifies if the App Group container is actually reachable.
    public func verifyAccess() -> Bool {
        let testKey = "vf_access_test"
        defaults?.set(true, forKey: testKey)
        let success = defaults?.bool(forKey: testKey) ?? false
        defaults?.removeObject(forKey: testKey)
        return success
    }
}
