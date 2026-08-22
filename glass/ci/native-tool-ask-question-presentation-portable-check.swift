import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeToolAskQuestionPresentationPortableCheck {
    static func main() throws {
        guard NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question", isRunning: true, isCompleted: false, errorCode: nil, textOutput: nil
        ) == .init(summary: .waiting, forcesStoppedState: false),
        NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question", isRunning: false, isCompleted: false, errorCode: "ASK_CANCELLED", textOutput: #"{"answers":[]}"#
        ) == .init(summary: .cancelled, forcesStoppedState: false),
        NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question", isRunning: false, isCompleted: false, errorCode: "ASK_ABORTED", textOutput: #"{"answers":[]}"#
        ) == .init(summary: .interrupted, forcesStoppedState: true) else {
            throw CheckFailure(description: "ask_user_question must prioritize running and explicit composer verdict summaries")
        }
        guard NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question", isRunning: false, isCompleted: true, errorCode: nil,
            textOutput: #"{"answers":[{"selected":["A"]},{"custom":"why"},{"selected":[]},{"custom":""}]}"#
        )?.summary == .answered(answered: 2, total: 4) else {
            throw CheckFailure(description: "settled ask_user_question must count selected or custom answers only")
        }
        guard NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question", isRunning: false, isCompleted: true, errorCode: nil, textOutput: "not JSON"
        )?.summary == .generic,
        NativeToolAskQuestionPresentation.resolve(
            toolName: "fx_ask_user_question", isRunning: false, isCompleted: true, errorCode: nil, textOutput: #"{"answers":[]}"#
        ) == nil else {
            throw CheckFailure(description: "malformed or unregistered question rows must retain generic fallback")
        }
        print("native tool ask-question presentation portable check passed")
    }
}
