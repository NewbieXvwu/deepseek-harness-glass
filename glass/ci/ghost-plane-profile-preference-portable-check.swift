import Foundation

@main
struct GhostPlaneProfilePreferencePortableCheck {
    static func main() {
        precondition(GhostPlaneProfilePreference.decode(nil).selection == .sharedWeb)
        let isolated = GhostPlaneProfilePreference(selection: .isolated(name: "review"))
        precondition(isolated.storedValue == "isolated:review")
        precondition(GhostPlaneProfilePreference.decode(isolated.storedValue).selection == .isolated(name: "review"))
        precondition(GhostPlaneProfilePreference.decode("file:///tmp").selection == .sharedWeb)
    }
}
