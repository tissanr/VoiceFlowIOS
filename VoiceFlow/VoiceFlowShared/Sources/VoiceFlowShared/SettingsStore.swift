import Foundation

/// `VoiceFlowSettings` in App Group suite preferences: small, readable from the keyboard.
public struct SettingsStore {
    public static let key = "settings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func appGroup() throws -> SettingsStore {
        guard let defaults = UserDefaults(suiteName: VoiceFlowConstants.appGroupIdentifier) else {
            throw SharedStoreError.appGroupUnavailable(suiteName: VoiceFlowConstants.appGroupIdentifier)
        }
        return SettingsStore(defaults: defaults)
    }

    public func load() -> VoiceFlowSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(VoiceFlowSettings.self, from: data)
        else { return .defaults }
        return settings
    }

    public func save(_ settings: VoiceFlowSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }
}
