import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Scene identity shared by launch, snapshot, and the native AppKit shell.
/// The actual application root is `NativeShellController`, which directly owns
/// the NSSplitViewController hierarchy required for real three-pane layout.
@MainActor
struct NativeAppShell: View {
    enum PresentationMode: Equatable {
        case welcome
        case conversation
        case tooling
        case approval
        case question
    }

    let mode: PresentationMode
    let viewportWidth: CGFloat
    let darkAppearance: Bool

    init(
        mode: PresentationMode = .welcome,
        viewportWidth: CGFloat = 1280,
        darkAppearance: Bool = false
    ) {
        self.mode = mode
        self.viewportWidth = viewportWidth
        self.darkAppearance = darkAppearance
    }

    /// This view remains a non-window preview seat. Production and snapshot
    /// rendering use NativeShellController for complete AppKit containment.
    var body: some View {
        Color.clear
            .environment(\.colorScheme, darkAppearance ? .dark : .light)
    }
}
