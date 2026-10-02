// Platform-lifecycle diagnostic, not an iPhone workflow or a substitute for testing SyncCenter.
import Foundation
import Network

func awaitFirstPath(_ monitor: NWPathMonitor, label: String) -> Bool {
    let signal = DispatchSemaphore(value: 0)
    monitor.pathUpdateHandler = { _ in signal.signal() }
    monitor.start(queue: DispatchQueue(label: "previously.audit.\(label)"))
    return signal.wait(timeout: .now() + 2) == .success
}

let original = NWPathMonitor()
let first = awaitFirstPath(original, label: "original")
original.cancel()
Thread.sleep(forTimeInterval: 0.2)
let reused = awaitFirstPath(original, label: "reused")
let replacement = NWPathMonitor()
let fresh = awaitFirstPath(replacement, label: "replacement")
replacement.cancel()
original.cancel()
print("originalDelivered=\(first) canceledObjectDelivered=\(reused) replacementDelivered=\(fresh)")
precondition(first && !reused && fresh, "Platform lifecycle outcome changed; investigate before claiming reproduction")
