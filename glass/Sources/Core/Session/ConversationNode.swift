import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// One raw Host event and the optional Host-rendered tool presentation carried
/// with session history and live mux frames. Node reducers always retain this
/// raw boundary; no SwiftUI renderer decodes an event body.
struct ConversationEventInput {
    let event: SessionEventDTO
    let view: ToolEventViewDTO?

    init(entry: SessionHistoryEntryDTO) {
        self.event = entry.event
        self.view = entry.view
    }

    init(event: SessionEventDTO, view: ToolEventViewDTO? = nil) {
        self.event = event
        self.view = view
    }
}

/// A node definition may accept one event as the unique context beginning or a
/// later state update. An update before start and a second start are reducer
/// invariant violations, not renderer recovery cases.
enum ConversationMatchRole: String, Equatable {
    case start
    case update
}

struct ConversationMatchResult: Equatable {
    let id: String
    let role: ConversationMatchRole
}

/// Publication cadence requested by accepted evidence. The reducer coalesces
/// the greatest value from a transaction instead of letting individual views
/// inspect raw events to decide when to refresh.
enum ConversationPublication: Int, Comparable {
    case none = 0
    case animationFrame = 1
    case immediate = 2

    static func < (lhs: ConversationPublication, rhs: ConversationPublication) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func maximum(_ lhs: ConversationPublication, _ rhs: ConversationPublication) -> ConversationPublication {
        lhs >= rhs ? lhs : rhs
    }
}

/// Immutable resolved Agent-step facts at the point one event is reduced.
struct ConversationStepLocation {
    enum Status: String, Equatable {
        case open
        case closed
        case unknown
    }

    let turn: Int
    let step: Int
    let start: SessionEventDTO?
    let end: SessionEventDTO?
    let status: Status
    let data: ConversationLocationDataStore
}

/// Immutable resolved Agent-turn facts at the point one event is reduced.
struct ConversationTurnLocation {
    enum Status: String, Equatable {
        case open
        case closed
        case unknown
    }

    let turn: Int
    let start: SessionEventDTO?
    let end: SessionEventDTO?
    let status: Status
    let steps: [ConversationStepLocation]
    let data: ConversationLocationDataStore
}

/// Engine-owned placement of a matched raw event in the session timeline.
enum ConversationLocation {
    case session
    case turn(ConversationTurnLocation)
    case step(turn: ConversationTurnLocation, step: ConversationStepLocation)
    case unresolved
}

/// Node-owned, read-only business values attached to the engine-owned turn or
/// step timeline. The storage remains a Core reducer concern.
struct ConversationLocationData {
    enum Scope: String, Equatable {
        case step
        case turn
    }

    let scope: Scope
    let turn: Int
    let step: Int?
    let key: String
    let value: Any
}

/// Reference-stable lookup surface for location data. It does not expose a
/// mutable dictionary to Definition implementations.
struct ConversationLocationDataStore {
    private let values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func value<Value>(for key: String, as: Value.Type = Value.self) -> Value? {
        values[key] as? Value
    }
}

/// Full evidence accepted by a definition for one stable business identity.
struct ConversationMatch {
    let input: ConversationEventInput
    let role: ConversationMatchRole
    let location: ConversationLocation

    var event: SessionEventDTO { input.event }
    var view: ToolEventViewDTO? { input.view }
}

/// General target-neutral render unit. The final SwiftUI target renderer reads
/// `data` only after the reducer materializes a typed node; it never receives
/// `SessionEventDTO` or parses an event body.
struct ConversationViewNode {
    let key: String
    let kind: String
    let id: String
    let target: String
    let data: Any
}

/// Chat-specific render identity. Visibility is explicit rather than removing
/// the node so incremental target builders retain stable keys while a node is
/// temporarily hidden.
struct ChatConversationViewNode {
    enum Visibility: String, Equatable {
        case visible
        case hidden
    }

    let node: ConversationViewNode
    let anchorSeq: Int
    let location: ConversationLocation
    let visibility: Visibility

    init(
        key: String,
        kind: String,
        id: String,
        data: Any,
        anchorSeq: Int,
        location: ConversationLocation,
        visibility: Visibility
    ) {
        self.node = ConversationViewNode(key: key, kind: kind, id: id, target: "chat", data: data)
        self.anchorSeq = anchorSeq
        self.location = location
        self.visibility = visibility
    }
}

/// Read-only node state exposed to node definitions. A reducer is the sole
/// owner that can adopt returned State; neither definitions nor renderers are
/// handed mutable assembly storage.
struct ConversationNodeContext<State> {
    let key: String
    let kind: String
    let id: String
    let matches: [ConversationMatch]
    let start: ConversationMatch?
    let state: State?
    let current: [String: ConversationViewNode?]
}

struct ConversationPreviousContext<State> {
    let key: String
    let kind: String
    let id: String
    let startSeq: Int
    let state: State
    let matches: [ConversationMatch]
}

/// Strictly-backward predecessor lookup available only while an accepted start
/// is evaluated. Implementations must record dependencies in their reducer.
protocol ConversationContextReader {
    func previous<State>(kind: String, as: State.Type) -> ConversationPreviousContext<State>?
}

/// One independently owned Event-to-Node reducer. The complete protocol is
/// intentionally Core-only: its `match`, `start`, `update`, `publication`,
/// location publication, and node construction run before UI receives output.
protocol ConversationNodeDefinition {
    associatedtype State

    var kind: String { get }
    /// Omit target for state-only contexts; one definition owns at most one target.
    var target: String? { get }

    func match(_ event: SessionEventDTO) -> ConversationMatchResult?
    func start(
        context: ConversationNodeContext<State>,
        match: ConversationMatch,
        reader: any ConversationContextReader
    ) -> State
    func update(
        context: ConversationNodeContext<State>,
        match: ConversationMatch
    ) -> State
    func publication(for match: ConversationMatch) -> ConversationPublication
    func buildLocationData(
        context: ConversationNodeContext<State>,
        scope: ConversationLocationData.Scope
    ) -> ConversationLocationData?
    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode?
}

extension ConversationNodeDefinition {
    func publication(for _: ConversationMatch) -> ConversationPublication { .immediate }
    func buildLocationData(
        context _: ConversationNodeContext<State>,
        scope _: ConversationLocationData.Scope
    ) -> ConversationLocationData? { nil }
    func buildViewNode(context _: ConversationNodeContext<State>) -> ConversationViewNode? { nil }
}

/// Type-erased definition retained by the Session-owned assembler. It preserves
/// a single reducer transaction boundary while allowing definitions with
/// independent state types to coexist in the same session registry.
struct AnyConversationNodeDefinition {
    let kind: String
    let target: String?

    private let matchBody: (SessionEventDTO) -> ConversationMatchResult?
    private let startBody: (ConversationNodeContext<Any>, ConversationMatch, any ConversationContextReader) -> Any
    private let updateBody: (ConversationNodeContext<Any>, ConversationMatch) -> Any
    private let publicationBody: (ConversationMatch) -> ConversationPublication
    private let locationDataBody: (ConversationNodeContext<Any>, ConversationLocationData.Scope) -> ConversationLocationData?
    private let viewNodeBody: (ConversationNodeContext<Any>) -> ConversationViewNode?

    init<Definition: ConversationNodeDefinition>(_ definition: Definition) {
        kind = definition.kind
        target = definition.target
        matchBody = definition.match
        startBody = { context, match, reader in
            definition.start(
                context: ConversationNodeContext<Definition.State>(
                    key: context.key,
                    kind: context.kind,
                    id: context.id,
                    matches: context.matches,
                    start: context.start,
                    state: context.state as? Definition.State,
                    current: context.current
                ),
                match: match,
                reader: reader
            )
        }
        updateBody = { context, match in
            guard let state = context.state as? Definition.State else {
                preconditionFailure("conversation Definition \(definition.kind) received an incompatible State")
            }
            return definition.update(
                context: ConversationNodeContext<Definition.State>(
                    key: context.key,
                    kind: context.kind,
                    id: context.id,
                    matches: context.matches,
                    start: context.start,
                    state: state,
                    current: context.current
                ),
                match: match
            )
        }
        publicationBody = definition.publication
        locationDataBody = { context, scope in
            definition.buildLocationData(
                context: ConversationNodeContext<Definition.State>(
                    key: context.key,
                    kind: context.kind,
                    id: context.id,
                    matches: context.matches,
                    start: context.start,
                    state: context.state as? Definition.State,
                    current: context.current
                ),
                scope: scope
            )
        }
        viewNodeBody = { context in
            definition.buildViewNode(
                context: ConversationNodeContext<Definition.State>(
                    key: context.key,
                    kind: context.kind,
                    id: context.id,
                    matches: context.matches,
                    start: context.start,
                    state: context.state as? Definition.State,
                    current: context.current
                )
            )
        }
    }

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? { matchBody(event) }
    func start(
        context: ConversationNodeContext<Any>,
        match: ConversationMatch,
        reader: any ConversationContextReader
    ) -> Any { startBody(context, match, reader) }
    func update(context: ConversationNodeContext<Any>, match: ConversationMatch) -> Any {
        updateBody(context, match)
    }
    func publication(for match: ConversationMatch) -> ConversationPublication { publicationBody(match) }
    func buildLocationData(
        context: ConversationNodeContext<Any>,
        scope: ConversationLocationData.Scope
    ) -> ConversationLocationData? { locationDataBody(context, scope) }
    func buildViewNode(context: ConversationNodeContext<Any>) -> ConversationViewNode? { viewNodeBody(context) }
}

/// Engine-owned, collision-free context identity equivalent to upstream
/// `conversationContextKey`: the prefixed kind length makes arbitrary ids safe
/// without assuming that a delimiter never appears in either component.
func conversationContextKey(kind: String, id: String) -> String {
    "\(kind.utf8.count):\(kind)\(id)"
}
