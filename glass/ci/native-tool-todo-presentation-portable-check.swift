import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeToolTodoPresentationPortableCheck {
    static func main() throws {
        guard let parallel = NativeToolTodoPresentation.resolve(
            toolName: "todo_write",
            arguments: #"{"todos":[{"content":"done","status":"completed"},{"content":"write renderer","status":"in_progress"},{"content":"run checks","status":"in_progress"},{"content":"later","status":"pending"}]}"#
        ), parallel == .init(done: 1, total: 4, activeContent: "write renderer", activeExtra: 1) else {
            throw CheckFailure(description: "todo_write must project completed/total plus first active content and non-shrinking parallel suffix")
        }
        guard let invalidFirst = NativeToolTodoPresentation.resolve(
            toolName: "todo_write",
            arguments: #"{"todos":[{"content":" ","status":"in_progress"},{"content":"later","status":"in_progress"}]}"#
        ), invalidFirst.activeContent == nil, invalidFirst.activeExtra == 0 else {
            throw CheckFailure(description: "todo summary must not skip an unusable first active item or invent its parallel suffix")
        }
        guard NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: #"{"todos":[null]}"#) == nil,
              NativeToolTodoPresentation.resolve(toolName: "fx_todo_write", arguments: #"{"todos":[]}"#) == nil,
              NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: "not JSON") == nil else {
            throw CheckFailure(description: "malformed or non-keyed todo inputs must retain the generic tool row fallback")
        }
        print("native tool todo presentation portable check passed")
    }
}
