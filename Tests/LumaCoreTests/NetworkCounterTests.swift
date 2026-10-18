import Foundation
import Darwin
import Testing
@testable import LumaCore

@Suite("Bounded native 64-bit interface counters") struct NetworkCounterTests {
    private func record(version: UInt8 = UInt8(RTM_VERSION), size: UInt16? = nil) -> Data {
        var value = if_msghdr2()
        value.ifm_msglen = size ?? UInt16(MemoryLayout<if_msghdr2>.size)
        value.ifm_version = version; value.ifm_type = UInt8(RTM_IFINFO2)
        value.ifm_index = 7; value.ifm_flags = IFF_UP | IFF_RUNNING
        value.ifm_data.ifi_ibytes = 8_000_000_000; value.ifm_data.ifi_obytes = 5_000_000_000
        value.ifm_data.ifi_lastchange.tv_sec = 123
        return withUnsafeBytes(of: value) { Data($0) }
    }
    @Test func fullWidthCountersAndAdministrativeGenerationAreRetained() throws {
        var data = Data([4, 0, UInt8(RTM_VERSION), 0x7f])
        data.append(record())
        let values = try NetworkCounters.decode(data)
        #expect(values.count == 1 && values[0].index == 7 && values[0].generation == "123:0")
        #expect(values[0].active && !values[0].loopback && values[0].received == 8_000_000_000 && values[0].sent == 5_000_000_000)
    }
    @Test func truncatedCorruptAndUnknownRecordsNeverBecomeZeroCounters() {
        for data in [Data([1]), record(size: 0), record(size: 3), Data(record().dropLast()), record(version: 0)] {
            #expect(throws: (any Error).self) { try NetworkCounters.decode(data) }
        }
    }
    @Test func oversizedResponsesAndExcessiveInterfacesAreRejectedAsAWhole() {
        #expect(throws: (any Error).self) { try NetworkCounters.decode(Data(repeating: 0, count: 2_097_153)) }
        let one = record()
        var data = Data()
        for _ in 0..<129 { data.append(one) }
        #expect(throws: (any Error).self) { try NetworkCounters.decode(data) }
    }
}
