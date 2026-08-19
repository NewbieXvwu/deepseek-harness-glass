import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Host-authoritative per-session projection values.
///
/// Mirrors the locked Web runtime's `ProjectionValueStore`: a history-tail
/// baseline and live `session/projection` frames both update `(sessionID, key)`
/// rows under the single higher-sequence-wins rule. Feature code receives only
/// completed Host values; it must never fold projection domain events locally.
@MainActor
final class SessionProjectionStore: ObservableObject {
    struct Row: Equatable {
        let value: JSONValue
        let seq: Int
    }

    private var rowsBySession: [String: [String: Row]] = [:]

    func value(sessionID: String, key: String) -> JSONValue? {
        rowsBySession[sessionID]?[key]?.value
    }

    func row(sessionID: String, key: String) -> Row? {
        rowsBySession[sessionID]?[key]
    }

    func values(sessionID: String) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: (rowsBySession[sessionID] ?? [:]).map { ($0.key, $0.value.value) })
    }

    func apply(sessionID: String, key: String, value: JSONValue, seq: Int) {
        let existing = rowsBySession[sessionID]?[key]
        guard existing == nil || seq > existing!.seq else { return }
        rowsBySession[sessionID, default: [:]][key] = Row(value: value, seq: seq)
    }

    /// Seed the consistent history-tail cut. Keys omitted by the Host baseline
    /// are capability-absent at that cut and clear only rows no newer than it.
    func seed(sessionID: String, baseline: SessionProjectionsDTO) {
        for (key, value) in baseline.values {
            apply(sessionID: sessionID, key: key, value: value, seq: baseline.asOfSeq)
        }
        guard var rows = rowsBySession[sessionID] else { return }
        for (key, row) in rows where baseline.values[key] == nil && row.seq <= baseline.asOfSeq {
            rows.removeValue(forKey: key)
        }
        rowsBySession[sessionID] = rows
    }

    /// Drop transient values beyond a reconnect's durable Host watermark.
    func truncate(sessionID: String, after lastSeq: Int) {
        guard var rows = rowsBySession[sessionID] else { return }
        rows = rows.filter { $0.value.seq <= lastSeq }
        rowsBySession[sessionID] = rows
    }

    func remove(sessionID: String) {
        rowsBySession.removeValue(forKey: sessionID)
    }

    func removeAll() {
        rowsBySession.removeAll()
    }
}
