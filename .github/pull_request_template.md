## 变更摘要（Summary）

<!-- 一句话：这次改了什么、为什么。 -->

## 变更范围

<!-- 勾选并简述：Sources / Tests / tools / docs / workflows -->

- [ ] Sources（生产代码）
- [ ] Tests（测试新增/修改/删除）
- [ ] tools / workflows
- [ ] docs / notes

## 自检清单（提交 PR 前必须全部完成）

- [ ] `swift build --package-path glass` 通过
- [ ] `swift test --package-path glass` 全绿
- [ ] `python3 tools/check-markdown-links.py` 通过
- [ ] 测试断言是精确/行为断言（`XCTAssertEqual` 明确期望值），不是：恒真、mirror 复制实现、`contains` 模糊匹配、盲等 `Task.sleep` 代替 expectation、只测不崩溃

## 变更后 CI 预期

- [ ] `build` workflow 预期全绿

## 审核要点（供 reviewer）

<!-- 若无特殊说明，reviewer 按 CONTRIBUTING.md 的质量红线审核。 -->
