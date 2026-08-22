import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Shared 8-cell dot matrix used by every native status dot rendering. Kept in
/// one place so session/row dots cannot silently fork their geometry.
enum NativeStateDotMetrics {
    static let matrixCells: [(CGFloat, CGFloat)] = [
        (0, 0), (4, 0), (8, 0), (8, 4),
        (8, 8), (4, 8), (0, 8), (0, 4),
    ]
}

/// Native visual counterpart of RC8 `ui-primitives/StateDot`. It has no
/// accessibility surface of its own; its adjacent typed status label remains
/// the semantic control/row description.
struct NativeStateDot: View {
    enum State: Equatable {
        case done
        case warning
        case ongoing
        case error
    }

    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var solidColor: Color {
        switch state {
        case .done:
            OfficialUISpec.Token.success
        case .warning:
            OfficialUISpec.Token.warningPrimary
        case .ongoing:
            OfficialUISpec.Token.stateDotOngoing
        case .error:
            OfficialUISpec.Token.errorPrimary
        }
    }

    var body: some View {
        Group {
            if state == .ongoing {
                ongoingMatrix
            } else {
                ZStack {
                    Circle().fill(solidColor.opacity(0.1))
                    Circle().fill(solidColor)
                        .frame(
                            width: OfficialUISpec.Geometry.px6,
                            height: OfficialUISpec.Geometry.px6
                        )
                }
            }
        }
        .frame(
            width: OfficialUISpec.Geometry.px10,
            height: OfficialUISpec.Geometry.px10
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ongoingMatrix: some View {
        if reduceMotion {
            matrix(phase: 0)
        } else {
            TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
                let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 8)
                    .quotientAndRemainder(dividingBy: NativeStateDotMetrics.matrixCells.count).remainder
                matrix(phase: phase)
            }
        }
    }

    private func matrix(phase: Int) -> some View {
        Canvas { context, size in
            let scaleX = size.width / OfficialUISpec.Geometry.px10
            let scaleY = size.height / OfficialUISpec.Geometry.px10
            for (index, cell) in NativeStateDotMetrics.matrixCells.enumerated() {
                let lag = (phase - index + NativeStateDotMetrics.matrixCells.count) % NativeStateDotMetrics.matrixCells.count
                let opacity: Double
                switch lag {
                case 0:
                    opacity = 1
                case 1:
                    opacity = 0.6
                case 2:
                    opacity = 0.35
                default:
                    opacity = 0.15
                }
                let rect = CGRect(
                    x: cell.0 * scaleX,
                    y: cell.1 * scaleY,
                    width: OfficialUISpec.Geometry.px2 * scaleX,
                    height: OfficialUISpec.Geometry.px2 * scaleY
                )
                context.fill(Path(rect), with: .color(solidColor.opacity(opacity)))
            }
        }
    }
}
