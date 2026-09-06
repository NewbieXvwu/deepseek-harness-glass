import Foundation

enum RemoteEndpoint: String, Sendable {
    case events = "$events"
    case eventsResult = "$events/result"
    case agentPresetsCopy = "agentPresets/copy"
    case agentPresetsDeletePreset = "agentPresets/deletePreset"
    case agentPresetsList = "agentPresets/list"
    case agentPresetsRead = "agentPresets/read"
    case agentPresetsSelect = "agentPresets/select"
    case credentialsDescribe = "credentials/describe"
    case credentialsSet = "credentials/set"
    case credentialsUnset = "credentials/unset"
    case goalsEdit = "goals/edit"
    case goalsPause = "goals/pause"
    case goalsResume = "goals/resume"
    case goalsClear = "goals/clear"
    case llmDiscoverModels = "llm/discoverModels"
    case llmListConfigurableProviders = "llm/listConfigurableProviders"
    case llmListProviders = "llm/listProviders"
    case messageFeedbackDelete = "messageFeedback/delete"
    case messageFeedbackList = "messageFeedback/list"
    case messageFeedbackPut = "messageFeedback/put"
    case sessionCanOpenWorkspacePath = "session/canOpenWorkspacePath"
    case sessionCancel = "session/cancel"
    case sessionControl = "session/control"
    case sessionCreate = "session/create"
    case sessionFollow = "session/follow"
    case sessionFork = "session/fork"
    case sessionList = "session/list"
    case sessionModelCatalog = "session/modelCatalog"
    case sessionOpenWorkspacePath = "session/openWorkspacePath"
    case sessionPage = "session/page"
    case sessionPrompt = "session/prompt"
    case sessionRename = "session/rename"
    case sessionSearch = "session/search"
    case sessionSelectModel = "session/selectModel"
    case sessionUpdateQueue = "session/updateQueue"
    case settingsCanOpenAgentPresetDirectory = "settings/canOpenAgentPresetDirectory"
    case settingsDescribe = "settings/describe"
    case settingsMutate = "settings/mutate"
    case settingsOpenAgentPresetDirectory = "settings/openAgentPresetDirectory"
    case subagentsInterruptByParent = "subagents/interruptByParent"
    case subagentsList = "subagents/list"
    case subagentsPrompt = "subagents/prompt"
    case workspaceArchiveSession = "workspace/archiveSession"
    case workspaceCreate = "workspace/create"
    case workspaceDelete = "workspace/delete"
    case workspaceFollow = "workspace/follow"
    case workspaceInsertBefore = "workspace/insertBefore"
    case workspaceInsertSessionBefore = "workspace/insertSessionBefore"
    case workspaceRename = "workspace/rename"
}

struct RemoteProcedure<Arguments: Encodable & Sendable, Output: Decodable & Sendable>: Sendable {
    let endpoint: RemoteEndpoint
    let timeout: TimeInterval

    init(_ endpoint: RemoteEndpoint, timeout: TimeInterval = 30) {
        self.endpoint = endpoint
        self.timeout = timeout
    }
}
