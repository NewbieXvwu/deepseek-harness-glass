import XCTest
@testable import GlassCore

final class PermissionPresetProjectionTests: XCTestCase {
    func testProjectsDynamicHostPresetOptionsAndAdvertisedMutationOnly() {
        let state = PermissionPresetProjection.state(
            namespaces: [permissionNamespace(value: "workspace-write", revision: 7)],
            writable: true
        )

        XCTAssertEqual(state.status, .ready)
        XCTAssertTrue(state.writable)
        XCTAssertEqual(state.currentValue, "workspace-write")
        XCTAssertEqual(state.revision, 7)
        XCTAssertEqual(state.options, [
            .init(id: "read-only", label: "Read Only", requiresConfirmation: false),
            .init(id: "workspace-write", label: "Workspace Write", requiresConfirmation: false),
            .init(id: "danger-full-access", label: "Full access", requiresConfirmation: true),
        ])
        guard case let .set(path, value)? = state.mutation(selecting: "workspace-write") else {
            return XCTFail("expected an advertised writable preset mutation")
        }
        XCTAssertEqual(path, ["defaultPreset"])
        XCTAssertEqual(value.stringValue, "workspace-write")
        XCTAssertNil(state.mutation(selecting: "invented"), "unknown preset must never reach transport")
    }

    func testDisplayNormalizesOnlyStrictASCIILowerKebabCaseWithoutRegex() {
        XCTAssertEqual(PermissionPresetProjection.display(value: "read-only", suppliedLabel: "read-only"), "Read Only")
        XCTAssertEqual(PermissionPresetProjection.display(value: "workspace-write", suppliedLabel: "Workspace"), "Workspace Write")
        XCTAssertEqual(PermissionPresetProjection.display(value: "release-2026", suppliedLabel: "release-2026"), "Release 2026")
        XCTAssertEqual(PermissionPresetProjection.display(value: "danger-full-access", suppliedLabel: "danger-full-access"), "Full access")

        for label in ["", "-leading", "trailing-", "double--dash", "Upper-case", "naïve-mode", "with_space"] {
            XCTAssertEqual(
                PermissionPresetProjection.display(value: "custom", suppliedLabel: label),
                label,
                "invalid non-kebab label must remain Host-authoritative and verbatim: \(label)"
            )
        }
    }

    func testFailsClosedForAbsentMalformedOrNonWritablePermissionDescriptor() {
        let unavailable = PermissionPresetProjection.state(namespaces: [], writable: true)
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertFalse(unavailable.writable)
        XCTAssertNil(unavailable.mutation(selecting: "read-only"))

        let malformed = PermissionPresetProjection.state(
            namespaces: [permissionNamespace(value: "missing", revision: 2)],
            writable: true
        )
        XCTAssertEqual(malformed.status, .malformed)
        XCTAssertFalse(malformed.writable)
        XCTAssertTrue(malformed.options.isEmpty)

        let readonly = PermissionPresetProjection.state(
            namespaces: [permissionNamespace(value: "read-only", revision: 3)],
            writable: false
        )
        XCTAssertEqual(readonly.status, .ready)
        XCTAssertFalse(readonly.writable)
        XCTAssertNil(readonly.mutation(selecting: "workspace-write"))
    }

    private func permissionNamespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "permission",
            schema: .object([
                "uid": .number(6),
                "refs": .object([
                    "1": .object(["type": .string("const"), "value": .string("read-only")]),
                    "2": .object([
                        "type": .string("const"),
                        "meta": .object(["description": .string("Workspace")]),
                        "value": .string("workspace-write"),
                    ]),
                    "3": .object(["type": .string("const"), "value": .string("danger-full-access")]),
                    "4": .object(["type": .string("union"), "list": .array([.number(1), .number(2), .number(3)])]),
                    "6": .object(["type": .string("object"), "dict": .object(["defaultPreset": .number(4)])]),
                ]),
            ]),
            value: .object(["defaultPreset": .string(value)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }
}
