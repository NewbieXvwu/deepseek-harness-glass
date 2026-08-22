import XCTest
@testable import GlassSpec

final class OfficialUISpecBuildTests: XCTestCase {
    func testGeneratedBuildIdentityIsCompleteAndSelfCompatible() {
        XCTAssertFalse(OfficialUISpec.Build.isCompatible(with: "unknown-host-build"))
        XCTAssertTrue(OfficialUISpec.Build.localeRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.tokenRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.layoutRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.fixtureRevision.hasPrefix("sha256:"))
        XCTAssertEqual(OfficialUISpec.Build.sourceCommit.count, 40)
        XCTAssertFalse(OfficialUISpec.Build.uiSpecRevision.isEmpty)
    }

    func testGeneratedBilingualLocaleCatalogIsQueryableAndMatchesBuildRevision() {
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.sourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.sourceInputRevision, OfficialUISpec.Build.localeRevision)
        XCTAssertNotEqual(OfficialUISpec.LocaleCatalog.revision, OfficialUISpec.Build.localeRevision)
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "en"))
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "zh"))
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "en"), "New Session")
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "zh"), "新会话")
        XCTAssertNil(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "not.registered", language: "en"))
    }
}


extension OfficialUISpecBuildTests {
    func testPackagedLocaleCatalogMatchesCompiledRuntimeValuesAndBilingualContract() {
        let catalog = OfficialLocaleRuntimeCatalog.catalog
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.sourceCommit, OfficialUISpec.LocaleCatalog.sourceCommit)
        XCTAssertEqual(catalog.localeRevision, OfficialUISpec.LocaleCatalog.revision)
        XCTAssertEqual(catalog.sourceInputRevision, OfficialUISpec.LocaleCatalog.sourceInputRevision)
        XCTAssertEqual(Set(catalog.languages), OfficialUISpec.LocaleCatalog.supportedLanguages)
        XCTAssertEqual(catalog.valueMap, OfficialUISpec.LocaleCatalog.values)

        let byID = Dictionary(grouping: catalog.entries, by: \.id)
        XCTAssertFalse(byID.isEmpty)
        for entries in byID.values {
            XCTAssertEqual(Set(entries.map(\.language)), Set(["en", "zh"]))
            XCTAssertEqual(Set(entries.map(\.interpolationParameters)).count, 1)
            XCTAssertEqual(Set(entries.map(\.pluralCategory)).count, 1)
        }
        XCTAssertNil(OfficialUISpec.LocaleCatalog.value(namespace: "not-an-official-namespace", key: "missing", language: "en"))
    }

    func testPackagedAccessibilityBaselineDecodesAndResolvesOfficialRuntimeLabels() {
        let baseline = OfficialAccessibilityBaselineCatalog.baseline
        XCTAssertEqual(baseline.schemaVersion, 1)
        XCTAssertEqual(baseline.officialSourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertNotNil(baseline.principles["macOSDynamicType"])
        XCTAssertEqual(Set(baseline.corePaths.map(\.scene)).count, 6)
        XCTAssertEqual(Set(baseline.requiredEnvironmentMarkers), [
            "accessibilityReduceMotion",
            "accessibilityReduceTransparency",
            "colorSchemeContrast",
            "colorScheme",
        ])
        XCTAssertEqual(
            baseline.requiredEnvironmentMarkers.count,
            Set(baseline.requiredEnvironmentMarkers).count,
            "the versioned accessibility baseline must not silently duplicate an environment marker"
        )

        for corePath in baseline.corePaths {
            guard let labels = OfficialAccessibilityBaselineCatalog.resolvedLabels(for: corePath.scene) else {
                XCTFail("baseline scene has an unresolved runtime label mapping: \(corePath.scene)")
                continue
            }
            XCTAssertFalse(labels.isEmpty)
            XCTAssertTrue(labels.allSatisfy(OfficialAccessibilityBaselineCatalog.isRegisteredAccessibilityLabel))
            XCTAssertTrue(
                corePath.source.hasPrefix("Sources/") && corePath.source.hasSuffix(".swift"),
                "baseline core path must retain its reviewed native Swift source"
            )
            XCTAssertFalse(
                corePath.focusContract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "baseline core path must retain a non-empty focus contract"
            )
        }
        XCTAssertNil(OfficialAccessibilityBaselineCatalog.resolvedLabels(for: "not-an-official-scene"))
        XCTAssertFalse(OfficialAccessibilityBaselineCatalog.isRegisteredAccessibilityLabel("not-an-official-accessibility-label"))
    }

    func testGeneratedOfficialThemeCatalogMatchesLockedBuildAndResolvesSchemes() {
        XCTAssertEqual(OfficialUISpec.Theme.sourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(OfficialUISpec.Theme.sourceInputRevision, OfficialUISpec.Build.tokenRevision)
        XCTAssertTrue(OfficialUISpec.Theme.revision.hasPrefix("sha256:"))
        XCTAssertEqual(OfficialUISpec.Theme.colorTokens.count, 162)

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
}


extension OfficialUISpecBuildTests {
    func testOfficialColumnLayoutMatchesEveryGeneratedComputeColumnsFixture() {
        let catalog = OfficialColumnLayoutFixtureCatalog.catalog
        XCTAssertEqual(catalog.sourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(catalog.source.path, OfficialColumnLayoutFixtureCatalog.lockedSourcePath)
        XCTAssertEqual(catalog.source.sha256, OfficialColumnLayoutFixtureCatalog.lockedSourceSHA256)
        XCTAssertGreaterThanOrEqual(catalog.fixtures.count, 30)

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
