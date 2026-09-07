import Foundation

struct HarnessControllers: Sendable {
    let sessions: SessionController
    let workspaces: WorkspaceController
    let goals: GoalController
    let subagents: SubagentController
    let messageFeedback: MessageFeedbackController
    let settings: SettingsController
    let credentials: CredentialsController
    let llm: LLMController
    let agentPresets: AgentPresetsController

    init(remote: RemoteConnection) {
        sessions = SessionController(remote: remote)
        workspaces = WorkspaceController(remote: remote)
        goals = GoalController(remote: remote)
        subagents = SubagentController(remote: remote)
        messageFeedback = MessageFeedbackController(remote: remote)
        settings = SettingsController(remote: remote)
        credentials = CredentialsController(remote: remote)
        llm = LLMController(remote: remote)
        agentPresets = AgentPresetsController(remote: remote)
    }
}
