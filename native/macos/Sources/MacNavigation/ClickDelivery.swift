import ApplicationServices
import Foundation

/// Coordinates worker-queue clicks with main-thread cancellation and shutdown.
/// Cancellation sets its token before calling finish(), so a worker cannot post
/// a new mouse-down after shutdown has released the pending mouse-up.
final class ClickDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingUp: CGEvent?
    private let post: (CGEvent) -> Void
    init(post: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }) { self.post = post }
    func begin(down: CGEvent, up: CGEvent, isCancelled: () -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard pendingUp == nil, !isCancelled() else { return false }
        pendingUp = up
        post(down)
        return true
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard let up = pendingUp else { return }
        post(up)
        pendingUp = nil
    }
}
