import Foundation

struct RemoteApprovalInteraction: Sendable, Equatable {
    let eventID: String
    let sessionID: String
    let toolName: String
    let callID: String?
    let reason: String?
}

struct RemoteQuestionInteraction: Sendable, Equatable {
    struct Option: Sendable, Equatable {
        let label: String
        let description: String?
    }

    enum Intent: Sendable, Equatable {
        case planReview(approve: String)
    }

    struct Item: Sendable, Equatable {
        let id: String
        let question: String
        let detail: String?
        let header: String?
        let options: [Option]
        let multiSelect: Bool
        let intent: Intent?
    }

    let eventID: String
    let sessionID: String
    let questions: [Item]
}

enum RemoteSessionInteractionUpdate: Sendable, Equatable {
    case approval(RemoteApprovalInteraction)
    case question(RemoteQuestionInteraction)
    case cancelled(eventID: String)
}

enum RemoteInteractionProjector {
    static func project(_ frame: RemoteEventDownlinkFrame) -> RemoteSessionInteractionUpdate? {
        switch frame {
        case let .waterfall(event, eventID, agentID, request):
            switch event {
            case "approval/request":
                guard let toolName = string(request["toolName"]) else { return nil }
                return .approval(.init(
                    eventID: eventID,
                    sessionID: agentID,
                    toolName: toolName,
                    callID: string(request["callId"]),
                    reason: string(request["reason"])
                ))
            case "user-questions/request":
                guard case let .array(rawQuestions)? = request["questions"] else { return nil }
                let questions = rawQuestions.compactMap(question)
                guard questions.count == rawQuestions.count, !questions.isEmpty else { return nil }
                return .question(.init(eventID: eventID, sessionID: agentID, questions: questions))
            default:
                return nil
            }
        case let .cancel(eventID):
            return .cancelled(eventID: eventID)
        case .ready, .emit:
            return nil
        }
    }

    private static func question(_ value: RemoteJSONValue) -> RemoteQuestionInteraction.Item? {
        guard case let .object(object) = value,
              let id = string(object["id"]),
              let question = string(object["question"])
        else { return nil }

        let options: [RemoteQuestionInteraction.Option]
        if let raw = object["options"] {
            guard case let .array(values) = raw else { return nil }
            options = values.compactMap(option)
            guard options.count == values.count else { return nil }
        } else {
            options = []
        }

        let multiSelect: Bool
        if let raw = object["multiSelect"] {
            guard case let .bool(value) = raw else { return nil }
            multiSelect = value
        } else {
            multiSelect = false
        }

        let intent: RemoteQuestionInteraction.Intent?
        if let raw = object["intent"] {
            guard case let .object(intentObject) = raw,
                  string(intentObject["kind"]) == "plan-review",
                  let approve = string(intentObject["approve"])
            else { return nil }
            intent = .planReview(approve: approve)
        } else {
            intent = nil
        }

        return .init(
            id: id,
            question: question,
            detail: string(object["detail"]),
            header: string(object["header"]),
            options: options,
            multiSelect: multiSelect,
            intent: intent
        )
    }

    private static func option(_ value: RemoteJSONValue) -> RemoteQuestionInteraction.Option? {
        guard case let .object(object) = value,
              let label = string(object["label"])
        else { return nil }
        return .init(label: label, description: string(object["description"]))
    }

    private static func string(_ value: RemoteJSONValue?) -> String? {
        guard case let .string(value)? = value else { return nil }
        return value
    }
}
