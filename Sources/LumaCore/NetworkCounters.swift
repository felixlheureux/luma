import Foundation
import Darwin

public struct NetworkCounterRecord: Sendable {
    public let index: UInt32
    public let generation: String
    public let active: Bool
    public let loopback: Bool
    public let received: UInt64
    public let sent: UInt64
}

/// Bounded decoder for the public NET_RT_IFLIST2/RTM_IFINFO2 format. Unknown
/// versions or truncated records disable this sample rather than inventing zero.
public enum NetworkCounters {
    public static func decode(_ data: Data) throws -> [NetworkCounterRecord] {
        guard data.count <= 2_097_152 else { throw LumaError.rejected("Interface counter data exceeds the collection limit.") }
        return try data.withUnsafeBytes { raw in
            var offset = 0, records: [NetworkCounterRecord] = []
            while offset < raw.count {
                guard offset + 4 <= raw.count else { throw LumaError.rejected("Incomplete interface counter header.") }
                let size = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard size >= 4, size <= raw.count - offset else { throw LumaError.rejected("Invalid interface counter record length.") }
                defer { offset += size }
                guard raw[offset + 3] == UInt8(RTM_IFINFO2) else { continue }
                guard raw[offset + 2] == UInt8(RTM_VERSION), size >= MemoryLayout<if_msghdr2>.size else {
                    throw LumaError.rejected("Unsupported or incomplete 64-bit interface counter format.")
                }
                guard records.count < 128 else { throw LumaError.rejected("Interface count limit reached.") }
                let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                records.append(.init(index: UInt32(info.ifm_index), generation: "\(info.ifm_data.ifi_lastchange.tv_sec):\(info.ifm_data.ifi_lastchange.tv_usec)",
                    active: info.ifm_flags & IFF_UP != 0 && info.ifm_flags & IFF_RUNNING != 0,
                    loopback: info.ifm_flags & IFF_LOOPBACK != 0,
                    received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes))
            }
            return records
        }
    }
}
