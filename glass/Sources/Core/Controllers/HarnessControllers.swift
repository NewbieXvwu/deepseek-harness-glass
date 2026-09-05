import Foundation

struct HarnessControllers: Sendable {
    let sessions: SessionController
    let workspaces: WorkspaceController
    let goals: GoalController
    let subagents: SubagentController

    init(remote: RemoteConnection) {
        sessions = SessionController(remote: remote)
        workspaces = WorkspaceController(remote: remote)
        goals = GoalController(remote: remote)
        subagents = SubagentController(remote: remote)
    }
}
