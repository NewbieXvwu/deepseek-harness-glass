import Foundation

struct OfficialAccessibilityBaseline: Decodable, Equatable {
    struct CorePath: Decodable, Equatable {
        let scene: String
        let requiredLabels: [String]
        let focusContract: String
    }

    let schemaVersion: Int
    let officialSourceCommit: String
    let principles: [String: String]
    let corePaths: [CorePath]
    let requiredEnvironmentMarkers: [String]
}

enum OfficialAccessibilityBaselineCatalog {
    static let baseline: OfficialAccessibilityBaseline = {
        guard let url = Bundle.module.url(forResource: "official-accessibility-baseline", withExtension: "json"),
              let decoded = try? JSONDecoder().decode(OfficialAccessibilityBaseline.self, from: Data(contentsOf: url))
        else {
            preconditionFailure("The packaged official accessibility baseline must decode at runtime.")
        }
        return decoded
    }()

    static let labelValues: [String: String] = [
        "newSessionAccessibility": OfficialUISpec.Text.newSessionAccessibility,
        "collapseSidebarAccessibility": OfficialUISpec.Text.collapseSidebarAccessibility,
        "openSidebarAccessibility": OfficialUISpec.Text.openSidebarAccessibility,
        "settings": OfficialUISpec.Text.settings,
        "composerDefaultPlaceholder": OfficialUISpec.Text.composerDefaultPlaceholder,
        "sendMessageAccessibility": OfficialUISpec.Text.sendMessageAccessibility,
        "commandsAccessibility": OfficialUISpec.Text.commandsAccessibility,
        "closeDetailsAccessibility": OfficialUISpec.Text.closeDetailsAccessibility,
        "approvalDetailsAccessibility": OfficialUISpec.Text.approvalDetailsAccessibility,
        "questionCancelAccessibility": OfficialUISpec.Text.questionCancelAccessibility,
        "questionPreviousAccessibility": OfficialUISpec.Text.questionPreviousAccessibility,
        "questionNextAccessibility": OfficialUISpec.Text.questionNextAccessibility,
    ]

    static func resolvedLabels(for scene: String) -> [String]? {
        guard let path = baseline.corePaths.first(where: { $0.scene == scene }) else { return nil }
        let values = path.requiredLabels.compactMap { labelValues[$0] }
        return values.count == path.requiredLabels.count ? values : nil
    }

    static func isRegisteredAccessibilityLabel(_ value: String) -> Bool {
        OfficialUISpec.LocaleCatalog.values.values.contains(value)
    }
}
