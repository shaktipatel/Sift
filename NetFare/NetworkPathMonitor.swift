import Foundation
import Network
import Combine

struct NetworkPathSnapshot: Equatable, Sendable {
    var isSatisfied: Bool = false
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var interface: NetworkInterfaceKind = .unknown

    var statusText: String {
        if !isSatisfied { return "Offline" }
        if isConstrained { return "Low Data Mode" }
        if isExpensive { return "Metered connection" }
        return interface.displayName
    }
}

@MainActor
final class NetworkPathMonitor: ObservableObject {
    @Published private(set) var snapshot = NetworkPathSnapshot()

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.netfare.path-monitor", qos: .utility)
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = NetworkPathSnapshot(
                isSatisfied: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                interface: Self.interface(for: path)
            )
            Task { @MainActor [weak self] in
                self?.snapshot = snapshot
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isRunning else { return }
        monitor?.cancel()
        monitor = nil
        isRunning = false
    }

    nonisolated private static func interface(for path: NWPath) -> NetworkInterfaceKind {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.loopback) { return .loopback }
        if path.usesInterfaceType(.other) { return .other }
        return .unknown
    }

    deinit {
        monitor?.cancel()
    }
}
