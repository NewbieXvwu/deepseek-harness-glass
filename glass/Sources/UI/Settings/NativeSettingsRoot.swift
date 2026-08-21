import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native root for the official settings surface. It deliberately renders only
/// the typed Host descriptor and never synthesizes a writable field from a
/// missing schema/value pair.
struct NativeSettingsRoot: View {
    enum SectionID: String, CaseIterable, Identifiable {
        case general
        case models
        case plugins

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: NativeSettingsRoot.official(namespace: "ui-settings-general", key: "general.nav")
            case .models: NativeSettingsRoot.official(namespace: "ui-settings-models", key: "nav")
            case .plugins: NativeSettingsRoot.official(namespace: "ui-settings-plugins", key: "nav")
            }
        }
    }

    @ObservedObject var store: NativeSettingsStore
    let retry: () -> Void
    let close: () -> Void
    @State private var selection: SectionID? = .general

    var body: some View {
        NavigationSplitView {
            List(SectionID.allCases, selection: $selection) { section in
                Text(section.title).tag(Optional(section))
            }
            .navigationTitle(official(namespace: "ui-settings-general", key: "title"))
        } detail: {
            detail
        }
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(official(namespace: "ui-settings-plugins", key: "collapse"), action: close)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView(official(namespace: "locale", key: "loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: OfficialUISpec.Spacing.p12) {
                Text(official(namespace: "locale", key: "load.failed"))
                Button(official(namespace: "locale", key: "retry"), action: retry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            List {
                Section(selection?.title ?? SectionID.general.title) {
                    ForEach(store.namespaces, id: \.ns) { namespace in
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                            Text(namespace.ns)
                            Text(namespace.applies)
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                        }
                    }
                }
            }
        }
    }

    private static func official(namespace: String, key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: namespace, key: key, language: "en") ?? ""
    }
}
