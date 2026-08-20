import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI transport for a browser row/group drag. The owner retains all
/// business state; this delegate only converts local pointer geometry into the
/// RC8 before/after target half and requests one commit from that owner.
struct NativeWorkspaceDropDelegate: DropDelegate {
    let isActive: () -> Bool
    let half: (DropInfo) -> NativeWorkspaceBrowserOrdering.DropHalf
    let hover: (NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let drop: (NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let exited: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isActive()
    }

    func dropEntered(info: DropInfo) {
        guard isActive() else { return }
        hover(half(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isActive() else { return nil }
        hover(half(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        exited()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isActive() else { return false }
        return drop(half(info))
    }
}

extension View {
    /// Source: RC8 `rowHalf` / `workspaceGroupHalf`: the full target geometry
    /// decides whether an insertion anchor sits before or after that target.
    func nativeWorkspaceDropTarget(
        active: @escaping () -> Bool,
        hover: @escaping (NativeWorkspaceBrowserOrdering.DropHalf) -> Void,
        drop: @escaping (NativeWorkspaceBrowserOrdering.DropHalf) -> Bool,
        exited: @escaping () -> Void
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: NativeWorkspaceDropDelegate(
                            isActive: active,
                            half: { info in
                                info.location.y < proxy.size.height / 2 ? .before : .after
                            },
                            hover: hover,
                            drop: drop,
                            exited: exited
                        )
                    )
            }
        }
    }
}
