import Foundation

/// Raw rc.1 durable tool-call projector. It consumes only the verified Journal event window.
final class ToolInvocationProjector {
    private var byID: [String: SessionToolInvocation] = [:]
    private var order: [String] = []

    @discardableResult
    func replaceWindow(
        _ records: [RemoteSessionHistoryRecord],
        sessionCWD: String?
    ) -> [SessionToolInvocation] {
        byID.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        for record in records {
            accept(ConversationEventInput(remoteRecord: record).event, sessionCWD: sessionCWD)
        }
        return snapshot()
    }

    @discardableResult
    func append(
        _ event: RemoteSessionWireEvent,
        sessionCWD: String?
    ) -> [SessionToolInvocation] {
        appendInPlace(event, sessionCWD: sessionCWD)
        return snapshot()
    }

    /// Incremental engine hot path. It updates only keyed projector state and
    /// defers ordered snapshot materialization until the enclosing engine emits.
    func appendInPlace(
        _ event: RemoteSessionWireEvent,
        sessionCWD: String?
    ) {
        accept(ConversationEventInput(remoteEvent: event).event, sessionCWD: sessionCWD)
    }

    func snapshot() -> [SessionToolInvocation] {
        order.compactMap { byID[$0] }
    }

    private func accept(_ event: SessionEventDTO, sessionCWD: String?) {
        switch event.type {
        case "tool/call":
            acceptCall(event, sessionCWD: sessionCWD)
        case "tool/result":
            acceptResult(event)
        default:
            break
        }
    }

    private func acceptCall(_ event: SessionEventDTO, sessionCWD: String?) {
        guard let data = event.data.objectValue,
              let callID = data["callId"]?.stringValue,
              let name = data["name"]?.stringValue,
              let arguments = data["arguments"]?.stringValue,
              byID[callID] == nil
        else { return }

        byID[callID] = .init(
            id: callID,
            name: name,
            arguments: arguments,
            output: nil,
            textOutput: nil,
            errorName: nil,
            errorCode: nil,
            state: .running,
            sequence: event.seq,
            parentCallID: data["parentCallId"]?.stringValue,
            sessionCWD: sessionCWD
        )
        order.append(callID)
    }

    private func acceptResult(_ event: SessionEventDTO) {
        guard let data = event.data.objectValue,
              let message = data["message"]?.objectValue,
              let source = message["source"]?.objectValue,
              let callID = source["callId"]?.stringValue,
              var invocation = byID[callID]
        else { return }

        let error = data["error"]?.objectValue
        let errorName = error?["name"]?.stringValue
        let errorCode = error?["code"]?.stringValue
        let wrapper = toolResultWrapper(in: message, callID: callID)
        let content = wrapper?.content ?? []
        let isError = wrapper?.isError ?? (errorCode != nil)

        invocation.output = resultText(in: content, errorName: errorName, errorCode: errorCode)
        invocation.textOutput = textResult(in: content)
        invocation.errorName = errorName
        invocation.errorCode = errorCode
        invocation.resultContent = content
        invocation.resultMeta = data["meta"]
        invocation.resultIsError = isError
        invocation.state = errorCode == "interrupted" ? .stopped : (isError ? .failed : .completed)
        byID[callID] = invocation
    }

    private struct ToolResultWrapper {
        let content: [JSONValue]
        let isError: Bool
    }

    private func toolResultWrapper(
        in message: [String: JSONValue],
        callID: String
    ) -> ToolResultWrapper? {
        guard let values = message["content"]?.arrayValue else { return nil }
        if values.count == 1,
           let wrapper = values[0].objectValue,
           wrapper["type"]?.stringValue == "tool-result",
           wrapper["toolCallId"]?.stringValue == callID,
           let content = wrapper["content"]?.arrayValue {
            if wrapper["isError"] != nil && wrapper["isError"]?.boolValue == nil { return nil }
            return .init(content: content, isError: wrapper["isError"]?.boolValue ?? false)
        }
        return .init(content: values, isError: false)
    }

    private func resultText(
        in content: [JSONValue],
        errorName: String?,
        errorCode: String?
    ) -> String? {
        let parts = content.compactMap { block -> String? in
            if let object = block.objectValue,
               object["type"]?.stringValue == "text",
               let text = object["text"]?.stringValue {
                return text
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            guard let encoded = try? encoder.encode(block),
                  let rendered = String(data: encoded, encoding: .utf8)
            else { return nil }
            return rendered
        }
        return NativeToolResultTextPresentation.flatten(
            parts: parts,
            errorName: errorName,
            errorCode: errorCode
        )
    }

    private func textResult(in content: [JSONValue]) -> String? {
        let text = content.compactMap { block -> String? in
            guard let object = block.objectValue,
                  object["type"]?.stringValue == "text",
                  let value = object["text"]?.stringValue
            else { return nil }
            return value
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
