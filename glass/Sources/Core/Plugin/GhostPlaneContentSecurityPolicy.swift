import Foundation

/// Native-authored CSP for the content-empty Ghost Plane document. The policy
/// is deliberately independent of plugin manifest text: a plugin never gets
/// to widen `connect-src`, navigation, frames, workers, or the source origins.
public enum GhostPlaneContentSecurityPolicy {
    public static let value = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self'; font-src 'self'; connect-src dsh-glass-attachment:; object-src 'none'; base-uri 'none'; frame-src 'none'; worker-src 'none'; form-action 'none'"

    public static let metaTag = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(value)\">"

    /// Adds the fixed policy directly after the native skeleton's opening head
    /// tag. The host fails closed when it cannot locate a real head element;
    /// that prevents a caller from using an arbitrary HTML fragment as a plane.
    public static func inject(into nativeSkeletonHTML: String) -> String? {
        guard let headStart = nativeSkeletonHTML.range(of: "<head", options: .caseInsensitive),
              let tagEnd = nativeSkeletonHTML[headStart.lowerBound...].firstRange(of: ">") else {
            return nil
        }
        let prefix = nativeSkeletonHTML[..<tagEnd.upperBound]
        let suffix = nativeSkeletonHTML[tagEnd.upperBound...]
        return String(prefix) + metaTag + suffix
    }
}
