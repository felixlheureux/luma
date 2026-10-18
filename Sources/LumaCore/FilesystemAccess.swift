import Foundation
import Darwin

/// Background inspection and ordinary cleanup share the same conservative
/// capability. Logical remote size is never reported as locally inspected bytes.
public enum FilesystemCapability: String, Sendable {
    case local, providerManaged, dataless, network, unknown

    public var explanation: String {
        switch self {
        case .local: "Available for local inspection."
        case .providerManaged: "Cloud or provider-managed storage was skipped, including downloaded files. Manage it in Finder or its provider app."
        case .dataless: "Online-only content was skipped to avoid downloading it. Manage it in Finder."
        case .network: "Network storage is unavailable for local inspection or cleanup. Open it in Finder."
        case .unknown: "Local-only access could not be established. This location was skipped; review it in Finder."
        }
    }
}

public struct FilesystemAccessError: LocalizedError, Sendable {
    public let capability: FilesystemCapability
    public var errorDescription: String? { capability.explanation }
}

/// A synchronous scope only: never hold a thread I/O policy over an await.
/// Nested scopes restore their caller's setting, including on cancellation.
enum NonMaterializingIO {
    static func perform<T>(_ body: () throws -> T) throws -> T {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        guard previous >= 0,
              setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                            IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0 else {
            throw FilesystemAccessError(capability: .unknown)
        }
        let result = Result { try body() }
        guard setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous) == 0 else {
            throw FilesystemAccessError(capability: .unknown)
        }
        do { return try result.get() }
        catch let error as POSIXError where error.code == .EDEADLK {
            throw FilesystemAccessError(capability: .dataless)
        }
    }
}

public enum FilesystemAccess {
    // Test injection can only restrict access; it cannot override platform checks.
    @TaskLocal static var restriction: (@Sendable (URL) -> FilesystemCapability)?

    public static func capability(at url: URL) throws -> FilesystemCapability {
        do { try requireLocal(url); return .local }
        catch let error as FilesystemAccessError { return error.capability }
    }

    static func requireLocal(_ url: URL) throws {
        try NonMaterializingIO.perform { _ = try PinnedPath(url, rejectAliases: false) }
    }

    /// Called for every pinned ancestor and leaf before metadata/content access.
    /// Checks fresh URL values, never cached scan-time capabilities.
    static func check(_ url: URL, metadata: stat, descriptor: Int32) throws {
        if let restricted = restriction?(url), restricted != .local {
            throw FilesystemAccessError(capability: restricted)
        }
        guard metadata.st_flags & UInt32(SF_DATALESS) == 0 else {
            throw FilesystemAccessError(capability: .dataless)
        }
        var volume = statfs()
        guard fstatfs(descriptor, &volume) == 0 else { throw FilesystemAccessError(capability: .unknown) }
        guard volume.f_flags & UInt32(MNT_LOCAL) != 0 else { throw FilesystemAccessError(capability: .network) }

        // System-designated provider containers, independent of vendor names.
        // Check each ancestor so downloads and descendants remain excluded.
        let components = url.pathComponents
        if components.count >= 3, ["CloudStorage", "Mobile Documents"].contains(components.last ?? ""),
           components.dropLast().last == "Library" {
            throw FilesystemAccessError(capability: .providerManaged)
        }
        var fresh = URL.exactFileURL(path: url.path)
        fresh.removeAllCachedResourceValues()
        let values: URLResourceValues
        do { values = try fresh.resourceValues(forKeys: [.isUbiquitousItemKey]) }
        catch { throw FilesystemAccessError(capability: .unknown) }
        guard values.isUbiquitousItem != true else { throw FilesystemAccessError(capability: .providerManaged) }

        // Opaque provider metadata is exclusion evidence only. Never parse a
        // private attribute or treat its absence as proof of local ownership.
        let length = flistxattr(descriptor, nil, 0, 0)
        guard length >= 0, length <= 65_536 else { throw FilesystemAccessError(capability: .unknown) }
        if length > 0 {
            var names = [CChar](repeating: 0, count: length)
            let read = flistxattr(descriptor, &names, names.count, 0)
            guard read >= 0 else { throw FilesystemAccessError(capability: .unknown) }
            let attributes = names.prefix(read).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
            guard !attributes.contains(where: { $0.hasPrefix("com.apple.fileprovider.") || $0.hasPrefix("com.apple.CloudDocs") }) else {
                throw FilesystemAccessError(capability: .unknown)
            }
        }

        // A sync root is provider-owned even with all content downloaded.
        // ATTR_CMNEXT_EXT_FLAGS is a supported Darwin metadata attribute.
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_EXT_FLAGS)
        struct ExtendedFlags {
            var length: UInt32 = 0
            var returned = attribute_set_t()
            var flags: UInt64 = 0
        }
        var buffer = ExtendedFlags()
        let status = withUnsafeMutableBytes(of: &buffer) {
            fgetattrlist(descriptor, &request, $0.baseAddress!, $0.count, UInt32(FSOPT_ATTR_CMN_EXTENDED))
        }
        guard status == 0, buffer.length >= MemoryLayout<ExtendedFlags>.size,
              buffer.returned.forkattr & attrgroup_t(ATTR_CMNEXT_EXT_FLAGS) != 0 else {
            throw FilesystemAccessError(capability: .unknown)
        }
        guard buffer.flags & UInt64(EF_IS_SYNC_ROOT) == 0 else {
            throw FilesystemAccessError(capability: .providerManaged)
        }
    }
}
