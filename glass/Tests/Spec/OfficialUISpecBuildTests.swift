import XCTest
@testable import GlassSpec

final class OfficialUISpecBuildTests: XCTestCase {
    func testGeneratedBuildIdentityIsCompleteAndSelfCompatible() {
        XCTAssertEqual(OfficialUISpec.deepSeekHarnessCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(OfficialUISpec.hostBuildID, OfficialUISpec.Build.id)
        XCTAssertTrue(OfficialUISpec.Build.isCompatible(with: OfficialUISpec.hostBuildID))
        XCTAssertFalse(OfficialUISpec.Build.isCompatible(with: "unknown-host-build"))
        XCTAssertTrue(OfficialUISpec.Build.localeRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.tokenRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.layoutRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.fixtureRevision.hasPrefix("sha256:"))
        XCTAssertEqual(OfficialUISpec.Build.sourceCommit.count, 40)
        XCTAssertEqual(OfficialUISpec.sidebarBuildRevision, "141eb6f")
        XCTAssertEqual(OfficialUISpec.Text.sidebarFallbackBrand, "DSH Local Build")
        XCTAssertEqual(OfficialUISpec.Layout.sidebarLogoRowHeight, 60)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarBrandMarkSize, 24)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarBuildBadgeHeight, 16)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarNewSessionHeight, 38)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarNativeExpandedLeadingInset, 5)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarNativeExpandedFooterLeadingAdjustment, 5)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTopPadding, 12)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderLeadingPadding, 20)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTrailingPadding, 28)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTitleRowHeight, 32)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTabStripHeight, 35)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTabGap, 36)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTabLeadingPadding, 8)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderTabBottomPadding, 11)
        XCTAssertEqual(OfficialUISpec.Layout.sessionHeaderActiveBarHeight, 2)
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

    func testOfficialColumnLayoutExposesLockedComputeColumnsConstants() {
        XCTAssertEqual(OfficialUISpec.Layout.centerMinimum, 640)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarMinimum, 264)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarMaximum, 420)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarDefault, 280)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarCollapsed, 56)
        XCTAssertEqual(OfficialUISpec.Layout.sidebarAutoCollapse, 1024)
        XCTAssertEqual(OfficialUISpec.Layout.detailsMinimum, 300)
        XCTAssertEqual(OfficialUISpec.Layout.detailsMaximum, 520)
        XCTAssertEqual(OfficialUISpec.Layout.detailsDefault, 360)
    }
}
