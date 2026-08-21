import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// RC8's new-session preset seat. It is intentionally absent from a started
/// session: Host composition is fixed once the session is no longer blank.
struct NativeAgentPresetSeat: View {
    let session: SessionSummaryDTO
    @ObservedObject var store: NativeAgentPresetStore
    let select: (String) async -> Bool

    private var options: [AgentPresetEntryDTO] {
        NativeAgentPresetSeatPresentation.options(from: store.presets)
    }

    private var currentID: String {
        NativeAgentPresetSeatPresentation.currentID(session: session, roster: store.presets) ?? ""
    }

    private var currentLabel: String {
        options.first(where: { $0.id == currentID })?.name ?? currentID
    }

    var body: some View {
        if NativeAgentPresetSeatPresentation.isAvailable(for: session), !options.isEmpty, !currentID.isEmpty {
            Menu {
                ForEach(options) { preset in
                    Button {
                        Task { _ = await select(preset.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                            Text(preset.name ?? preset.id)
                            Text(preset.description ?? official(key: "noDescription"))
                                .font(OfficialUISpec.Typography.xs13)
                        }
                    }
                    .disabled(store.isSelecting || preset.id == currentID)
                }
            } label: {
                Label(currentLabel, systemImage: "person.crop.circle")
                    .font(OfficialUISpec.Typography.sStrong14)
            }
            .disabled(store.isSelecting)
            .accessibilityLabel(official(key: "seatHint"))
        }
    }

    private func official(key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-agent-preset", key: key, language: "en") ?? ""
    }
}
