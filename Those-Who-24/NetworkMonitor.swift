import Foundation
import Network

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    // Start optimistic so an online launch does not briefly flash offline UI.
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ThoseWho24.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = isConnected
            }
        }
        monitor.start(queue: queue)
    }
}
