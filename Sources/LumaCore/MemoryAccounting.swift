import Foundation

public struct MemoryBreakdown: Sendable {
    public let app: Int64
    public let wired: Int64
    public let compressed: Int64
    public let cached: Int64
    public let used: Int64
    public let available: Int64

    public init(physical: Int64, pageSize: Int64, anonymousPages: UInt64, wiredPages: UInt64,
                compressedPages: UInt64, purgeablePages: UInt64, fileBackedPages: UInt64) {
        let total = max(0, physical)
        let page = max(1, pageSize)
        let limit = UInt64(total / page)
        func bytes(_ pages: UInt64) -> Int64 { Int64(min(pages, limit)) * page }
        let anonymous = min(anonymousPages, limit)
        app = bytes(anonymous - min(anonymous, purgeablePages))
        wired = min(bytes(wiredPages), total - app)
        compressed = min(bytes(compressedPages), total - app - wired)
        used = app + wired + compressed
        available = total - used
        cached = min(bytes(min(fileBackedPages, limit)) + bytes(min(purgeablePages, limit)), available)
    }
}
