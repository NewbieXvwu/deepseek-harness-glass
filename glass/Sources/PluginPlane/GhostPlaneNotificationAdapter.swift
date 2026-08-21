import AppKit
import GlassCore
import UserNotifications

/// Native notification capability adapter for the registered Ghost Plane.
/// It deliberately owns the two-step user boundary: plugin capability approval
/// through `GhostPlanePermissionPromptPresenter`, followed by macOS system TCC.
@MainActor
public final class GhostPlaneNotificationAdapter {
    private let prompts: GhostPlanePermissionPromptPresenter
    private let center: UNUserNotificationCenter

    public init(
        prompts: GhostPlanePermissionPromptPresenter = .init(),
        center: UNUserNotificationCenter = .current()
    ) {
        self.prompts = prompts
        self.center = center
    }

    public func notify(
        pluginID: String,
        displayName: String,
        title: String,
        body: String
    ) async -> Bool {
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .notifications) == .granted else {
            return false
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return false }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
