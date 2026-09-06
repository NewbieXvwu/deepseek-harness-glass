import Foundation
import XCTest

@testable import GlassCore

final class WorkspaceRuntimeInvariantTests: XCTestCase {
    private func makeWorkspace(id: String, title: String = "Workspace") -> RemoteWorkspaceView {
        RemoteWorkspaceView(
            workspaceId: id,
            path: "/path/\(id)",
            title: title,
            sessionIds: ["s1", "s2"],
            createdAt: "2026-09-01T00:00:00Z",
            updatedAt: "2026-09-01T00:00:00Z"
        )
    }

    private func makeInitialState(count: Int = 5) -> WorkspaceRuntimeState {
        let items = (0..<count).map { makeWorkspace(id: "ws-\($0)", title: "Workspace \($0)") }
        return WorkspaceRuntimeState(
            generation: RemoteConnectionGeneration(rawValue: 1),
            items: items,
            archivedSessionIDs: ["arch-1"]
        )
    }

    // MARK: - 不变量 1：防御性排序保留集合守恒，杜绝幽灵项与数据丢失

    func testOrderPreservesExactSetOfExistingItemsUnderPartialOrUnknownOrder() {
        let initial = makeInitialState(count: 5)
        let initialIDs = Set(initial.items.map(\.workspaceId))

        // 仅给出部分 ID，并夹杂未知 ID 与重复 ID
        let chaoticOrder = ["ws-3", "unknown-99", "ws-1", "ws-3", "unknown-88"]
        let next = WorkspaceStateReducer.reduce(current: initial, frame: .order(chaoticOrder))

        // 集合守恒：一个都不多，一个都不少
        let nextIDs = Set(next.items.map(\.workspaceId))
        XCTAssertEqual(nextIDs, initialIDs, "Order 操作严禁增加幽灵工作区或丢失未提及的工作区")

        // 唯一性：结果中严禁出现重复项
        XCTAssertEqual(next.items.count, initial.items.count)

        // 相对顺序：排在前面的应为提及的已知项，且去重
        XCTAssertEqual(next.items[0].workspaceId, "ws-3")
        XCTAssertEqual(next.items[1].workspaceId, "ws-1")

        // 未提及的项应保留在末尾（保持原有相对顺序）
        let trailingIDs = next.items[2...].map(\.workspaceId)
        XCTAssertEqual(trailingIDs, ["ws-0", "ws-2", "ws-4"])
    }

    func testOrderWithEmptyOrAllUnknownIDsPreservesStateWithoutMutation() {
        let initial = makeInitialState(count: 4)

        let emptyResult = WorkspaceStateReducer.reduce(current: initial, frame: .order([]))
        XCTAssertEqual(emptyResult.items, initial.items, "空 order 帧必须保持当前工作区集合不变")

        let unknownResult = WorkspaceStateReducer.reduce(current: initial, frame: .order(["foo", "bar", "baz"]))
        XCTAssertEqual(unknownResult.items, initial.items, "纯未知 ID 的 order 帧必须保持当前工作区集合不变")
    }

    // MARK: - 不变量 2：重复与迟到 Baseline 的绝对幂等性

    func testDuplicateBaselineFrameIsIdempotentAndNeverThrowsOrClearsState() {
        let initial = makeInitialState(count: 3)
        let newBaseline = RemoteWorkspaceBaseline(
            items: [makeWorkspace(id: "ws-new-1")],
            archivedSessionIds: ["arch-new"]
        )

        // 收到重复或非法的 baseline 帧时，Reducer 必须幂等返回当前状态，绝不清除现有数据
        let next = WorkspaceStateReducer.reduce(current: initial, frame: .baseline(newBaseline))
        XCTAssertEqual(next, initial, "重复 baseline 帧必须安全短路忽略，不得破坏当前已建立的状态")
    }

    // MARK: - 不变量 3：Upsert 与 Remove 幂等性

    func testUpsertUpdatesExistingOrAppendsNewWithoutDuplication() {
        var state = makeInitialState(count: 2)

        // 更新已有项
        let updated = makeWorkspace(id: "ws-0", title: "Updated Title")
        state = WorkspaceStateReducer.reduce(current: state, frame: .upsert(updated))
        XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.items.first(where: { $0.workspaceId == "ws-0" })?.title, "Updated Title")

        // 追加新项
        let brandNew = makeWorkspace(id: "ws-new", title: "Brand New")
        state = WorkspaceStateReducer.reduce(current: state, frame: .upsert(brandNew))
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.items.last?.workspaceId, "ws-new")

        // 再次 upsert 相同项（幂等）
        state = WorkspaceStateReducer.reduce(current: state, frame: .upsert(brandNew))
        XCTAssertEqual(state.items.count, 3, "重复 upsert 严禁造成列表中存在重复 ID")
    }

    func testRemoveNonExistentIdIsSafeNoop() {
        let initial = makeInitialState(count: 3)
        let next = WorkspaceStateReducer.reduce(current: initial, frame: .remove("non-existent-id"))
        XCTAssertEqual(next, initial, "删除不存在的 ID 必须是安全空操作")
    }

    // MARK: - 不变量 4：1,000 次混沌随机风暴注入（Chaos Storm Injection）

    func testHighFrequencyChaosStormInvariantMaintenance() {
        var state = makeInitialState(count: 10)
        let initialItemCount = 10
        let iterationCount = 1000

        var rng = SplitMix64(seed: 42) // 确定性伪随机种子，保证回归可重现

        let startTime = Date()

        for step in 0..<iterationCount {
            let opKind = rng.nextInt(upperBound: 5)
            let frame: RemoteWorkspaceFollowFrame

            switch opKind {
            case 0:
                // 随机 Upsert：可能是更新已有的，也可能是插入全新的
                let id = "ws-\(rng.nextInt(upperBound: initialItemCount * 2))"
                frame = .upsert(makeWorkspace(id: id, title: "Step \(step)"))
            case 1:
                // 随机 Remove：可能存在，也可能不存在
                let id = "ws-\(rng.nextInt(upperBound: initialItemCount * 2))"
                frame = .remove(id)
            case 2:
                // 随机 Order：包含部分已知、部分未知、重复 ID、乱序
                let count = rng.nextInt(upperBound: 15)
                let ids = (0..<count).map { _ in "ws-\(rng.nextInt(upperBound: initialItemCount * 2))" }
                frame = .order(ids)
            case 3:
                // 迟到的 Baseline
                frame = .baseline(RemoteWorkspaceBaseline(items: [], archivedSessionIds: []))
            default:
                // Archived 更新
                let count = rng.nextInt(upperBound: 5)
                let sessionIDs = (0..<count).map { "session-\($0)" }
                frame = .archived(sessionIDs)
            }

            state = WorkspaceStateReducer.reduce(current: state, frame: frame)

            // 【每步核心不变量校验】
            // 1. 列表中 ID 必须严格唯一，绝对不可出现重复元素
            let ids = state.items.map(\.workspaceId)
            let uniqueIDs = Set(ids)
            XCTAssertEqual(
                ids.count,
                uniqueIDs.count,
                "在第 \(step) 步混沌操作后，工作区列表出现了重复 ID！"
            )

            // 2. 状态结构完整可用，不得有 nil 或非法字段
            XCTAssertEqual(state.generation.rawValue, 1)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        // 性能契约：1,000 次纯函数状态机重排必须在 50ms 内瞬间完成
        XCTAssertLessThan(elapsed, 0.05, "1,000 次混沌状态迭代耗时 \(elapsed)s，超过 50ms 性能预算！")
    }
}

/// 快速且确定性的伪随机发生器，避免测试依赖系统随机源
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}
