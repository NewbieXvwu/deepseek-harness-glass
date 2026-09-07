from pathlib import Path

STORE = Path("glass/Sources/Core/Session/NativeSessionStore.swift")
SHELL = Path("glass/Sources/UI/Shell/NativeSplitContainer.swift")


def replace_once(text: str, source: str, target: str, label: str) -> str:
    count = text.count(source)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(source, target, 1)


def function_block(text: str, marker: str) -> tuple[int, int, str]:
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"missing function marker: {marker}")
    end = text.find("\n    func ", start + len(marker))
    if end < 0:
        end = len(text)
    return start, end, text[start:end]


shell = SHELL.read_text()
shell = replace_once(
    shell,
    "        sessionStore.bindCommandService(SessionCommandService(controller: controllers.sessions))\n",
    "        sessionStore.bindCommandService(SessionCommandService(\n"
    "            controller: controllers.sessions,\n"
    "            interactions: eventRuntime\n"
    "        ))\n",
    "production command service injection",
)
SHELL.write_text(shell)

store = STORE.read_text()

# Approval: domain command service owns the production Remote waterfall reply.
start, end, block = function_block(store, "    func answerApproval(allowOnce: Bool) {\n")
block = replace_once(
    block,
    "              remoteEventRuntime != nil || (api != nil && approval.approvalID != nil),\n",
    "              sessionCommandService != nil || (api != nil && approval.approvalID != nil),\n",
    "approval availability",
)
block = replace_once(
    block,
    "        let eventRuntime = remoteEventRuntime\n",
    "        let commandService = sessionCommandService\n",
    "approval service capture",
)
block = replace_once(
    block,
    '''                if let eventRuntime {
                    try await eventRuntime.reply(
                        eventID: approval.eventID,
                        outcome: .result(.string(allowOnce ? "allowed-once" : "rejected"))
                    )
                } else if let legacyAPI, let approvalID = approval.approvalID {
''',
    '''                if let commandService {
                    try await commandService.answerApproval(
                        eventID: approval.eventID,
                        allowOnce: allowOnce
                    )
                } else if let legacyAPI, let approvalID = approval.approvalID {
''',
    "approval typed mutation",
)
store = store[:start] + block + store[end:]

# Question answer: map the UI-domain answer values once, then command service
# owns the official Remote outcome shape.
start, end, block = function_block(store, "    func answerQuestion(_ answers: [QuestionAnswer]) {\n")
block = replace_once(
    block,
    "              remoteEventRuntime != nil || api != nil,\n",
    "              sessionCommandService != nil || api != nil,\n",
    "question availability",
)
block = replace_once(
    block,
    "        let eventRuntime = remoteEventRuntime\n",
    "        let commandService = sessionCommandService\n",
    "question service capture",
)
branch_start = block.find("                if let eventRuntime {\n")
branch_end = block.find("                } else if let legacyAPI {\n", branch_start)
if branch_start < 0 or branch_end < 0:
    raise SystemExit("question typed branch bounds missing")
question_target = '''                if let commandService {
                    try await commandService.answerQuestion(
                        eventID: question.eventID,
                        answers: answers.map {
                            .init(id: $0.id, selected: $0.selected, custom: $0.custom)
                        }
                    )
'''
block = block[:branch_start] + question_target + block[branch_end:]
store = store[:start] + block + store[end:]

# Question cancellation follows the same ownership boundary.
start, end, block = function_block(store, "    func cancelQuestion() {\n")
block = replace_once(
    block,
    "              remoteEventRuntime != nil || api != nil,\n",
    "              sessionCommandService != nil || api != nil,\n",
    "question cancel availability",
)
block = replace_once(
    block,
    "        let eventRuntime = remoteEventRuntime\n",
    "        let commandService = sessionCommandService\n",
    "question cancel service capture",
)
block = replace_once(
    block,
    '''                if let eventRuntime {
                    try await eventRuntime.reply(
                        eventID: question.eventID,
                        outcome: .rejected(.init(
                            name: "UserQuestionError",
                            message: "the user cancelled ask_user_question",
                            code: "ASK_CANCELLED"
                        ))
                    )
                } else if let legacyAPI {
''',
    '''                if let commandService {
                    try await commandService.cancelQuestion(eventID: question.eventID)
                } else if let legacyAPI {
''',
    "question cancel typed mutation",
)
store = store[:start] + block + store[end:]

STORE.write_text(store)
