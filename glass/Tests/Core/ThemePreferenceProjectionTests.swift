import XCTest

@testable import GlassCore

final class ThemePreferenceProjectionTests: XCTestCase {
    func testOfficialThemePreferenceIsProjectedWithoutResolvingSystemAppearance() {
        let state = ThemePreferenceProjection.state(
            namespaces: [namespace(value: "system", revision: 8)],
            writable: true
        )

        XCTAssertEqual(state.status, .ready)
        XCTAssertEqual(state.current, .system)
        XCTAssertTrue(state.writable)
        XCTAssertEqual(state.revision, 8)
    }

    func testThemeMutationUsesOnlyOfficialNamespacePathAndEnum() {
        let state = ThemePreferenceProjection.state(
            namespaces: [namespace(value: "light", revision: 4)],
            writable: true
        )

        XCTAssertEqual(
            state.mutation(selecting: .dark),
            .set(path: ["preference"], value: .string("dark"))
        )
    }

    func testUnknownOrMissingThemeAuthorityCannotManufactureWritablePreference() {
        let unknown = ThemePreferenceProjection.state(
            namespaces: [namespace(value: "solarized", revision: 5)],
            writable: true
        )
        let missing = ThemePreferenceProjection.state(namespaces: [], writable: true)
        let readOnly = ThemePreferenceProjection.state(
            namespaces: [namespace(value: "dark", revision: 6)],
            writable: false
        )

        XCTAssertEqual(unknown.status, .malformed)
        XCTAssertNil(unknown.current)
        XCTAssertNil(unknown.mutation(selecting: .light))
        XCTAssertEqual(missing.status, .unavailable)
        XCTAssertNil(missing.mutation(selecting: .system))
        XCTAssertEqual(readOnly.status, .ready)
        XCTAssertFalse(readOnly.writable)
        XCTAssertNil(readOnly.mutation(selecting: .light))
    }

    private func namespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "ui-theme",
            schema: .object([:]),
            value: .object(["preference": .string(value)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }
}
