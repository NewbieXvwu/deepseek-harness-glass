import Foundation

@main
struct GhostPlaneCSPPortableCheck {
    static func main() {
        let html = GhostPlaneContentSecurityPolicy.inject(into: "<html><head></head><body></body></html>")
        precondition(html?.contains("default-src 'none'") == true)
        precondition(html?.contains("connect-src 'none'") == true)
        precondition(html?.contains("form-action 'none'") == true)
        precondition(html?.contains("script-src 'self'") == true)
        precondition(GhostPlaneContentSecurityPolicy.inject(into: "<div></div>") == nil)
    }
}
