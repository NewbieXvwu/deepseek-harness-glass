## 变更摘要（Summary）

<!-- 一句话：这次改了什么、为什么。 -->

## 变更范围

<!-- 勾选并简述：Sources / Tests / tools&ci / docs / workflows -->

- [ ] Sources（生产代码）
- [ ] Tests（测试新增/修改/删除）
- [ ] tools / ci / workflows
- [ ] docs / notes

## 自检清单（提交 PR 前必须全部完成）

- [ ] `cd glass && swift build` 通过
- [ ] 受影响测试通过：`swift test --filter <受影响套件>`
- [ ] 仓库门禁通过：
  - `python3 glass/ci/test-package-target-graph.py`
  - `python3 glass/ci/test-ci-workflow-layout.py`
  - `python3 glass/ci/check-test-integrity.py`（输出必须为 0 恒真断言命中）
- [ ] 无新增 `glass/ci/*portable-check.swift` 双轨文件；`.github/workflows/portable-checks.yml` 未重新引入 `portable-swift` job
- [ ] 测试断言是精确/行为断言（`XCTAssertEqual` 明确期望值），不是：恒真、mirror 复制实现、`contains` 模糊匹配、盲等 `Task.sleep` 代替 expectation、只测不崩溃
- [ ] 若新增测试：能杀死至少一个突变体（本地 `swift-mutation-testing` 或 review 时说明理由）

## 变更后 CI 预期

- [ ] `portable-checks` / `native-ui` 两个 workflow 预期全绿
- [ ] 若触及 `glass/Sources/PortableCore/**` 或 `Tests/PortableCore/**`：`mutation-testing` gate 预期通过（score ≥ 70%）

## 审核要点（供 reviewer）

<!-- 若无特殊说明，reviewer 按 CONTRIBUTING.md 的质量红线审核。 -->