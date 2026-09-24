import XCTest
@testable import GlassSpec

final class OfficialUISpecBuildTests: XCTestCase {
    func testGeneratedBilingualLocaleCatalogIsQueryable() {
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "en"))
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "zh"))
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "en"), "New Session")
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "zh"), "新会话")
        XCTAssertNil(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "not.registered", language: "en"))
        XCTAssertNil(OfficialUISpec.LocaleCatalog.value(namespace: "not-an-official-namespace", key: "missing", language: "en"))
    }

    func testGeneratedOfficialThemeCatalogResolvesSchemes() {
        let base = OfficialUISpec.Theme.value("--dsw-alias-bg-base")
        XCTAssertEqual(base.light, OfficialRGBA(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(
            base.dark,
            OfficialRGBA(
                red: 21.0 / 255.0,
                green: 21.0 / 255.0,
                blue: 23.0 / 255.0,
                alpha: 1
            )
        )

        let warning = OfficialUISpec.Theme.aliasStateWarnPrimary
        XCTAssertEqual(warning.light, OfficialRGBA(red: 245.0 / 255.0, green: 158.0 / 255.0, blue: 11.0 / 255.0, alpha: 1))
        XCTAssertEqual(warning.dark, warning.light)
    }

    func testOfficialColumnLayoutMatchesEveryGeneratedComputeColumnsFixture() throws {
        let catalog = try XCTUnwrap(OfficialColumnLayoutFixtureCatalog.catalog)
        XCTAssertFalse(catalog.fixtures.isEmpty)

        for fixture in catalog.fixtures {
            let actual = OfficialColumnLayout.resolve(
                viewport: fixture.viewport,
                sidebarPreference: fixture.sidebarPreference,
                detailsPreference: fixture.detailsPreference
            )
            XCTAssertEqual(
                actual,
                OfficialColumnLayout(
                    sidebar: fixture.expected.sidebar,
                    center: fixture.expected.center,
                    details: fixture.expected.details
                ),
                fixture.name
            )
        }
    }
}
