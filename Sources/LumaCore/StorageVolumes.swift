import Foundation
import Darwin

/// Volume capacity observations are separate from logical bytes in a scan.
/// UUID/device/mount/root-location evidence binds a result to this generation.
public struct StorageVolumeIdentity: Sendable, Equatable {
    public let uuid: String
    public let device: UInt64
    public let mountPath: String
    public let filesystemID: Data
}

public struct StorageVolume: Identifiable, Sendable {
    public var id: String { identity.mountPath }
    public let identity: StorageVolumeIdentity
    public let name: String
    public let filesystem: String
    public let isReadOnly: Bool
    public let capacity: Int64?
    public let free: Int64?
    public let availableForImportantUsage: Int64?

    public static func inspect(at url: URL) throws -> Self {
        try NonMaterializingIO.perform {
            let pin = try PinnedPath(url, allowInspectionRoot: true)
            var fs = statfs()
            guard fstatfs(pin.descriptor, &fs) == 0 else { throw PinnedPath.posixError() }
            let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeAvailableCapacityForImportantUsageKey])
            guard let uuid = values.volumeUUIDString, !uuid.isEmpty else {
                throw LumaError.rejected("This volume has no available stable identifier. Analyze a supported local volume.")
            }
            let mountPath = string(fs.f_mntonname)
            let identity = StorageVolumeIdentity(uuid: uuid, device: UInt64(UInt32(bitPattern: pin.value.st_dev)),
                mountPath: mountPath, filesystemID: withUnsafeBytes(of: fs.f_fsid) { Data($0) })
            try pin.revalidate()
            return Self(identity: identity, name: values.volumeName ?? URL(fileURLWithPath: mountPath).lastPathComponent,
                filesystem: string(fs.f_fstypename), isReadOnly: fs.f_flags & UInt32(MNT_RDONLY) != 0,
                capacity: bytes(fs.f_blocks, fs.f_bsize), free: bytes(fs.f_bfree, fs.f_bsize),
                availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage)
        }
    }

    public static func mounted() -> [Self] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { try? inspect(at: $0) }.sorted { Data($0.id.utf8).lexicographicallyPrecedes(Data($1.id.utf8)) }
    }

    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
    private static func bytes(_ blocks: UInt64, _ blockSize: UInt32) -> Int64? {
        let (value, overflow) = blocks.multipliedReportingOverflow(by: UInt64(blockSize))
        return overflow ? nil : Int64(exactly: value)
    }
}

public struct StorageScope: Sendable {
    public let root: URL
    public let volume: StorageVolume
    public let rootLocation: FileLocation
    public let inspectionOnly: Bool

    public static func capture(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Self {
        try NonMaterializingIO.perform {
            let pin = try PinnedPath(root, allowInspectionRoot: true)
            let volume = try StorageVolume.inspect(at: root)
            let homeDevice = try? PinnedPath(home).value.st_dev
            try pin.revalidate()
            return Self(root: root, volume: volume, rootLocation: pin.location,
                inspectionOnly: volume.isReadOnly || !Filesystem.isWithin(root, root: home) || pin.value.st_dev != homeDevice)
        }
    }

    public func validate() throws {
        let current = try Self.capture(root: root)
        guard current.volume.identity == volume.identity, current.volume.isReadOnly == volume.isReadOnly,
              current.rootLocation == rootLocation else {
            throw LumaError.rejected("The volume or analysis root changed. Choose the target and scan again.")
        }
    }
}
