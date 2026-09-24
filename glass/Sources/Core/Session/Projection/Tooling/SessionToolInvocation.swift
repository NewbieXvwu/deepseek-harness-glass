import Foundation

/// Transport-free rc.1 tool call/result projection value. Card projectors depend on this Core value, never MainActor Store state.
struct SessionToolInvocation: Identifiable, Sendable {
    enum State: Sendable, Equatable {
        case running
        case completed
        case failed
        case stopped
    }

    let id: String
    let name: String
    let arguments: String
    var output: String?
    /// Text-only flatten of the rc.1 inner `tool-result.content` array.
    var textOutput: String?
    /// Structured error is retained for generic fallback and stopped state.
    var errorName: String?
    var errorCode: String?
    var state: State
    let sequence: Int
    /// Raw rc.1 facts consumed by native card projectors. `resultContent` is
    /// the inner content of the durable `tool-result` wrapper; metadata is
    /// the top-level `tool/result.data.meta` value.
    var resultContent: [JSONValue]?
    var resultMeta: JSONValue?
    var resultIsError: Bool?
    var parentCallID: String?
    var sessionCWD: String?

    init(
        id: String,
        name: String,
        arguments: String,
        output: String?,
        textOutput: String?,
        errorName: String?,
        errorCode: String?,
        state: State,
        sequence: Int,
        resultContent: [JSONValue]? = nil,
        resultMeta: JSONValue? = nil,
        resultIsError: Bool? = nil,
        parentCallID: String? = nil,
        sessionCWD: String? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.output = output
        self.textOutput = textOutput
        self.errorName = errorName
        self.errorCode = errorCode
        self.state = state
        self.sequence = sequence
        self.resultContent = resultContent
        self.resultMeta = resultMeta
        self.resultIsError = resultIsError
        self.parentCallID = parentCallID
        self.sessionCWD = sessionCWD
    }
}
