import AppKit
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// The UI-side completion of the native download path. Core guarantees that the
/// URL is a collision-resolved file inside the selected native download policy;
/// this adapter deliberately never receives a Host URL or a browser download.
@MainActor
enum NativeSessionLogExportOpener {
    @discardableResult
    static func open(_ export: SessionLogExport) -> Bool {
        NSWorkspace.shared.open(export.fileURL)
    }
}
