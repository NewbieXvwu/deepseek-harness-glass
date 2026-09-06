import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Renderer-safe RC8 `permissions` whole projection. Source:
/// `interaction/permission-presets/src/types.ts:12-43`. This is deliberately
/// projection-backed rather than reconstructed from permission/sandbox/approval
/// events, because key absence means the optional permission capability is not
/// composed and the composer control must hide.
struct CoreSessionPermissionSelect: Equatable {
    struct Option: Equatable, Identifiable {
        let value: String
        let name: String
        let description: String?

        var id: String { value }
    }

    let currentValue: String
    let options: [Option]

    init?(projection: JSONValue) {
        guard let object = projection.objectValue,
              let currentValue = object["currentValue"]?.stringValue,
              !currentValue.isEmpty,
              let rawOptions = object["options"]?.arrayValue,
              !rawOptions.isEmpty
        else { return nil }

        var options: [Option] = []
        var seen = Set<String>()
        for raw in rawOptions {
            guard let option = raw.objectValue,
                  let value = option["value"]?.stringValue,
                  !value.isEmpty,
                  let name = option["name"]?.stringValue,
                  !name.isEmpty,
                  seen.insert(value).inserted
            else { return nil }
            let description = option["description"]?.stringValue
            options.append(.init(value: value, name: name, description: description))
        }

        guard options.contains(where: { $0.value == currentValue }) else { return nil }
        self.currentValue = currentValue
        self.options = options
    }

    func contains(_ value: String) -> Bool {
        options.contains(where: { $0.value == value })
    }
}

/// Projection reader that intentionally fails closed: an absent, null, or
/// malformed capability never exposes a locally invented permission picker.
@MainActor
enum SessionPermissionProjectionReader {
    static func value(from store: SessionProjectionStore, sessionID: String) -> CoreSessionPermissionSelect? {
        guard let projection = store.value(sessionID: sessionID, key: "permissions"), projection != .null else { return nil }
        return .init(projection: projection)
    }
}
