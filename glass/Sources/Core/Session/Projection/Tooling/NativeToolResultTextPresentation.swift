import Foundation

/// Foundation-only result-text projection matching rc.2
/// `tool-call-model.ts:resultText`. Core preserves block order and supplies each
/// non-text block as its own pretty JSON string; this model owns only the shared
/// join and empty-result error decision so a renderer cannot accidentally drop
/// an earlier text or non-text block.
public enum NativeToolResultTextPresentation {
    /// Joins every rendered content block with exactly one newline. Empty content
    /// is not replaced by invented prose: it becomes `name: code` only when the
    /// Host supplied both structured error fields, otherwise it remains absent.
    public static func flatten(
        parts: [String],
        errorName: String?,
        errorCode: String?
    ) -> String? {
        if !parts.isEmpty { return parts.joined(separator: "\n") }
        guard let errorName, let errorCode else { return nil }
        return "\(errorName): \(errorCode)"
    }
}
