import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import LumaCore

/// Public IOPowerSources is primary. The supported legacy read-only battery API
/// supplements cycle count only when both APIs describe one installed battery.
enum BatteryProvider {
    static func collect() -> BatteryDetails {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .init(issue: "The system power-source report is unavailable.")
        }
        let batteries = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .filter { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        guard !batteries.isEmpty else { return .init(presence: .notPresent) }
        guard batteries.count == 1, let values = batteries.first,
              let present = values[kIOPSIsPresentKey] as? Bool else { return .init(issue: "The internal battery report is incomplete or ambiguous.") }
        guard present else { return .init(presence: .notPresent) }
        var cycles: Int?
        var raw: Unmanaged<CFArray>?
        let status = IOPMCopyBatteryInfo(mach_port_t(MACH_PORT_NULL), &raw)
        if let records = raw?.takeRetainedValue() as? [[String: Any]], status == kIOReturnSuccess,
           records.count == 1, let record = records.first {
            cycles = record[kIOBatteryCycleCountKey] as? Int
        }
        return .init(presence: .available, input: .init(
            current: values[kIOPSCurrentCapacityKey] as? Int, maximum: values[kIOPSMaxCapacityKey] as? Int,
            nominal: values[kIOPSNominalCapacityKey] as? Int, design: values[kIOPSDesignCapacityKey] as? Int,
            charging: values[kIOPSIsChargingKey] as? Bool,
            externalPower: (values[kIOPSPowerSourceStateKey] as? String).flatMap { $0 == kIOPSACPowerValue ? true : $0 == kIOPSBatteryPowerValue ? false : nil },
            health: values[kIOPSBatteryHealthKey] as? String, condition: values[kIOPSBatteryHealthConditionKey] as? String,
            cycles: cycles, minutesToEmpty: values[kIOPSTimeToEmptyKey] as? Int, minutesToFull: values[kIOPSTimeToFullChargeKey] as? Int))
    }
}
