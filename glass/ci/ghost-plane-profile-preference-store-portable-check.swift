import Foundation

@main
struct GhostPlaneProfilePreferenceStorePortableCheck {
    static func main() {
        let suite = "GhostPlaneProfilePreferenceStorePortableCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GhostPlaneProfilePreferenceStore(defaults: defaults, key: "profile")
        precondition(store.preference.selection == .sharedWeb)
        store.set(.init(selection: .isolated(name: "review")))
        precondition(store.preference.selection == .isolated(name: "review"))
        precondition(defaults.string(forKey: "profile") == "isolated:review")
        store.reset()
        precondition(store.preference.selection == .sharedWeb)
    }
}
