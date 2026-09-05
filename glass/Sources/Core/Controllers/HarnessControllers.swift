import Foundation

struct HarnessControllers: Sendable {
    let sessions: SessionController
    let workspaces: WorkspaceController
    let goals: GoalController

    init(remote: RemoteConnection) {
        sessions = SessionController(remote: remote)
        workspaces = WorkspaceController(remote: remote)
        goals = GoalController(remote: remote)
    }
}
