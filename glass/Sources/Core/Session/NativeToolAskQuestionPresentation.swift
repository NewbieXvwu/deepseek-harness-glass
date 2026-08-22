import Foundation

/// Localized by the UI from the official conversation locale. Generic means the
/// keyed row retains the shared ToolRow summary because result text was invalid.
public enum NativeToolAskQuestionSummary: Equatable, Sendable {
    case waiting
    case cancelled
    case interrupted
    case answered(answered: Int, total: Int)
    case generic
}

/// Foundation-only projection of rc.2's `ask_user_question` keyed row summary.
/// It does not own composer takeover or answer submission; T9.3 owns that live
/// interaction and this model only renders a historical tool-row outcome.
public struct NativeToolAskQuestionPresentation: Equatable, Sendable {
    public let summary: NativeToolAskQuestionSummary
    /// `ASK_ABORTED` uses the shared stopped/amber row semantics, not failed.
    public let forcesStoppedState: Bool

    public init(summary: NativeToolAskQuestionSummary, forcesStoppedState: Bool) {
        self.summary = summary
        self.forcesStoppedState = forcesStoppedState
    }

    public static func resolve(
        toolName: String,
        isRunning: Bool,
        isCompleted: Bool,
        errorCode: String?,
        textOutput: String?
    ) -> NativeToolAskQuestionPresentation? {
        guard toolName == "ask_user_question" else { return nil }
        if errorCode == "ASK_CANCELLED" {
            return .init(summary: .cancelled, forcesStoppedState: false)
        }
        if errorCode == "ASK_ABORTED" {
            return .init(summary: .interrupted, forcesStoppedState: true)
        }
        if isRunning {
            return .init(summary: .waiting, forcesStoppedState: false)
        }
        guard isCompleted, let textOutput, let answered = answeredSummary(textOutput) else {
            return .init(summary: .generic, forcesStoppedState: false)
        }
        return .init(summary: answered, forcesStoppedState: false)
    }

    private static func answeredSummary(_ text: String) -> NativeToolAskQuestionSummary? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              let values = root as? [String: Any],
              let answers = values["answers"] as? [Any],
              answers.allSatisfy(isAnswer)
        else { return nil }
        let answered = answers.filter { answer in
            let selected = value(answer, key: "selected")
            let custom = value(answer, key: "custom")
            return (selected as? [Any])?.isEmpty == false || (custom as? String)?.isEmpty == false
        }.count
        return .answered(answered: answered, total: answers.count)
    }

    /// Mirrors JavaScript `typeof value === 'object' && value !== null`; arrays
    /// pass shape admission but have no `selected`/`custom` named fields.
    private static func isAnswer(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any] || value is NSDictionary || value is NSArray
    }

    private static func value(_ answer: Any, key: String) -> Any? {
        if let dictionary = answer as? [String: Any] { return dictionary[key] }
        if let dictionary = answer as? NSDictionary { return dictionary[key] }
        return nil
    }
}
