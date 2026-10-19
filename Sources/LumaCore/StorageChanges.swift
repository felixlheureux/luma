import Foundation
import CoreServices

/// Path-level invalidation hints. Luma-owned persistence never dirties discovery.
/// Missing event history returns all observed roots for conservative rediscovery.
public final class StorageChanges: @unchecked Sendable {
    private final class Pending: @unchecked Sendable {
        let lock = NSLock()
        var paths: Set<String> = []
        let roots: [URL]
        let excluded: URL
        init(roots: [URL], home: URL) { self.roots = roots; excluded = home.appendingPathComponent("Library/Application Support/Luma") }
        func record(_ paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>) {
            lock.lock(); defer { lock.unlock() }
            for (i, path) in paths.enumerated() {
                let gap = flags[i] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount) != 0
                if gap { self.paths.formUnion(roots.map(\.path)); continue }
                if !Filesystem.isWithin(URL(fileURLWithPath: path), root: excluded) { self.paths.insert(path) }
                if self.paths.count > 256 { self.paths = Set(roots.map(\.path)); break }
            }
        }
        func drain() -> [URL] { lock.lock(); defer { paths = []; lock.unlock() }; return paths.sorted().map { URL(fileURLWithPath: $0) } }
    }
    private let pending: Pending
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Luma.storage-changes", qos: .utility)
    public init(roots: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        pending = Pending(roots: roots, home: home)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(pending).toOpaque(),
            retain: { raw in
                guard let raw else { return nil }; _ = Unmanaged<Pending>.fromOpaque(raw).retain(); return UnsafeRawPointer(raw)
            }, release: { raw in if let raw { Unmanaged<Pending>.fromOpaque(raw).release() } }, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, context, count, rawPaths, flags, _ in
            guard let context else { return }
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as! [String]
            Unmanaged<Pending>.fromOpaque(context).takeUnretainedValue().record(Array(paths.prefix(count)), flags: flags)
        }, &context, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents)) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) { self.stream = stream }
        else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
    public func take() -> [URL] { pending.drain() }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
