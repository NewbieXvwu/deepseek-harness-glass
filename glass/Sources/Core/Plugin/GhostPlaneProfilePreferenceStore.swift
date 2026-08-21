import Foundation

/// App-local persistence for the Ghost Plane profile selection. This store is
/// intentionally separate from `NativeSettingsStore`: it records only the
/// safe codec string and cannot mutate remote Host descriptors or `DSH_HOME`.
public final class GhostPlaneProfilePreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = GhostPlaneProfilePreference.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public var preference: GhostPlaneProfilePreference {
        GhostPlaneProfilePreference.decode(defaults.string(forKey: key))
    }

    public func set(_ preference: GhostPlaneProfilePreference) {
        defaults.set(preference.storedValue, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
