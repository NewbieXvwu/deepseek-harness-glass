import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
@testable import GlassSnapshot
#endif
@MainActor
final class HostLifecycleCoordinator {
    private var hostController: HarnessHostController?
    private var externalHostController: ExternalHarnessHostController?
    private var observation: AnyCancellable?
    private let onState: (HostLifecycleState) -> Void

    init(onState: @escaping (HostLifecycleState) -> Void) {
        self.onState = onState
    }

    func start() {
        guard hostController == nil, externalHostController == nil else { return }
        do {
            let controller = try HarnessHostController()
            hostController = controller
            observe(controller.$state)
            controller.start()
        } catch {
            onState(.failed(HostFailure(
                kind: .launchFailed,
                message: "Could not initialize the bundled DeepSeek Harness Host: \(error.localizedDescription)",
                exitStatus: nil,
                logPath: ""
            )))
        }
    }

    func attachExternalHost(launchURL: URL) {
        stop()
        let controller = ExternalHarnessHostController()
        externalHostController = controller
        observe(controller.$state)
        controller.attach(launchURL: launchURL)
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        hostController?.stop()
        hostController = nil
        externalHostController?.stop()
        externalHostController = nil
    }

    private func observe(_ publisher: Published<HostLifecycleState>.Publisher) {
        observation = publisher.sink { [onState] state in onState(state) }
    }
}
