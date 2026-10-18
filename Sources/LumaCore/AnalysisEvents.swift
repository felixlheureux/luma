import Foundation
import CoreServices

/// Invalidation hints only: no traversal, content reads, or automatic scans.
/// Any event (including overflow, ID wrap, root change or unmount) invalidates
/// the entire authorized root. Missing history still falls back to fresh per-file
/// metadata and directory enumeration on every explicitly requested analysis.
final class AnalysisEvents {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64 = 0
        func increment() { lock.lock(); value &+= 1; lock.unlock() }
        func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    }
    private let counter = Counter()
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Luma.analysis-events", qos: .utility)
    init(root: URL, enabled: Bool = true) {
        guard enabled else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(counter).toOpaque(),
            retain: { raw in
                guard let raw else { return nil }
                _ = Unmanaged<Counter>.fromOpaque(raw).retain()
                return UnsafeRawPointer(raw)
            }, release: { raw in
                if let raw { Unmanaged<Counter>.fromOpaque(raw).release() }
            }, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, context, count, _, _, _ in
            guard let context, count > 0 else { return }
            Unmanaged<Counter>.fromOpaque(context).takeUnretainedValue().increment()
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) { self.stream = stream }
        else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
    func generation() -> UInt64 {
        if let stream { FSEventStreamFlushSync(stream) }
        return counter.read()
    }
    func invalidate() { counter.increment() }
    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
