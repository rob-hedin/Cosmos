import Foundation
import Metal

/// Reusable Metal buffers, safe to return from a command buffer's completion handler.
final class BufferPool: @unchecked Sendable {
    /// Carries a buffer to the completion handler; the GPU is done with it by then, so nothing races.
    struct Handoff: @unchecked Sendable {
        let buffer: MTLBuffer
    }

    private let lock = NSLock()
    private var buffers: [MTLBuffer] = []

    func take(minimumLength: Int) -> MTLBuffer? {
        lock.withLock {
            guard let index = buffers.firstIndex(where: { $0.length >= minimumLength }) else { return nil }
            return buffers.remove(at: index)
        }
    }

    func put(_ handoff: Handoff) {
        lock.withLock {
            // A few frames in flight is the most we'll ever need at once. When full, a larger
            // buffer replaces the smallest, so the pool keeps up after the label limit grows.
            if buffers.count >= 4 {
                guard let smallest = buffers.indices.min(by: { buffers[$0].length < buffers[$1].length }),
                      buffers[smallest].length < handoff.buffer.length
                else { return }
                buffers.remove(at: smallest)
            }
            buffers.append(handoff.buffer)
        }
    }
}
