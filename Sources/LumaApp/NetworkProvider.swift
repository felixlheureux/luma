import Foundation
import Darwin
import SystemConfiguration
import LumaCore

/// Passive local counters and interface metadata only. No sockets, DNS queries,
/// reachability probes, SSID lookups or per-application traffic attribution.
enum NetworkProvider {
    private static let epoch = ContinuousClock.now
    static func collect() -> NetworkObservation {
        let elapsed = epoch.duration(to: .now)
        let time = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        do {
            var addresses: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&addresses) == 0 else { throw POSIXError(.EIO) }
            defer { freeifaddrs(addresses) }
            var names: [UInt32: String] = [:], local: [String: Set<String>] = [:]
            var cursor = addresses, entries = 0
            while let item = cursor, entries < 4096 {
                entries += 1; cursor = item.pointee.ifa_next
                let name = String(cString: item.pointee.ifa_name)
                names[if_nametoindex(item.pointee.ifa_name)] = name
                guard let address = item.pointee.ifa_addr, [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    local[name, default: []].insert(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
                }
            }
            guard cursor == nil else { throw LumaError.rejected("Interface metadata limit reached.") }
            let store = SCDynamicStoreCreate(nil, "Luma passive network activity" as CFString, nil, nil)
            var primary: String?
            for family in ["IPv4", "IPv6"] where primary == nil {
                let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any]
                primary = state?["PrimaryInterface"] as? String
            }
            var kinds: [String: String] = [:]
            for interface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).prefix(128) {
                guard let name = SCNetworkInterfaceGetBSDName(interface) as String?, let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { continue }
                kinds[name] = type == (kSCNetworkInterfaceTypeIEEE80211 as String) ? "Wi-Fi" : type == (kSCNetworkInterfaceTypeEthernet as String) ? "Ethernet" : type
            }
            var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
            var length = 0
            guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0, length <= 2_097_152 else {
                throw LumaError.rejected("Interface counters unavailable or over the collection limit.")
            }
            var bytes = [UInt8](repeating: 0, count: length)
            guard sysctl(&mib, u_int(mib.count), &bytes, &length, nil, 0) == 0, length <= bytes.count else { throw POSIXError(.EIO) }
            let counters = try NetworkCounters.decode(Data(bytes.prefix(length)))
            guard !counters.isEmpty else { throw LumaError.rejected("No supported interface counter records were returned.") }
            let interfaces = counters.compactMap { counter -> NetworkInterfaceSample? in
                guard !counter.loopback, let name = names[counter.index] else { return nil }
                return .init(id: "\(name):\(counter.index):\(counter.generation)", name: name, kind: kinds[name] ?? "Other interface",
                    addresses: Array((local[name] ?? []).sorted().prefix(8)), active: counter.active,
                    received: counter.received, sent: counter.sent)
            }
            return .init(time: time, primaryInterface: primary, interfaces: interfaces.sorted { $0.name < $1.name })
        } catch { return .init(time: time, primaryInterface: nil, interfaces: [], issue: error.localizedDescription) }
    }
}
