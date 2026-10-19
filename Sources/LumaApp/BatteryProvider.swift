import Foundation
import IOKit.ps
import LumaCore

/// Lightweight public IOPowerSources only; slow details never run in the sample loop.
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
        var result = BatteryDetails(presence: .available, input: .init(
            current: values[kIOPSCurrentCapacityKey] as? Int, maximum: values[kIOPSMaxCapacityKey] as? Int,
            charging: values[kIOPSIsChargingKey] as? Bool,
            externalPower: (values[kIOPSPowerSourceStateKey] as? String).flatMap { $0 == kIOPSACPowerValue ? true : $0 == kIOPSBatteryPowerValue ? false : nil },
            health: values[kIOPSBatteryHealthKey] as? String, condition: values[kIOPSBatteryHealthConditionKey] as? String,
            minutesToEmpty: values[kIOPSTimeToEmptyKey] as? Int, minutesToFull: values[kIOPSTimeToFullChargeKey] as? Int,
            charged: values[kIOPSIsChargedKey] as? Bool, finishingCharge: values[kIOPSIsFinishingChargeKey] as? Bool))
        if let id = values[kIOPSPowerSourceIDKey] as? NSNumber, let name = values[kIOPSNameKey] as? String,
           let state = values[kIOPSPowerSourceStateKey] as? String {
            result.sourceIdentity = "\(id):\(name):\(state)"
        }
        return result
    }
}
