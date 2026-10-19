import Foundation
import CoreFoundation

/// Allowlisted fields observed in Apple's structured SPPowerDataType report on
/// Apple M2, macOS 27.0.1. No serial numbers or other hardware records are retained.
public struct BatteryPowerReport: Sendable {
    public var observedAt: Date
    public var condition: String?
    public var cycles: Int?
    public var maximumCapacityPercent: Double?

    public static func parse(_ data: Data, observedAt: Date) throws -> Self {
        guard data.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["SPPowerDataType"] as? [[String: Any]] else { throw ReportError.invalid }
        let batteries = records.filter { $0["_name"] as? String == "spbattery_information" }
        guard batteries.count == 1,
              let health = batteries[0]["sppower_battery_health_info"] as? [String: Any] else { throw ReportError.invalid }
        var result = Self(observedAt: observedAt)
        if let text = health["sppower_battery_health"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 128 { result.condition = text }
        if let number = health["sppower_battery_cycle_count"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0,
           number.doubleValue <= 1_000_000, number.doubleValue.rounded() == number.doubleValue { result.cycles = number.intValue }
        // The verified schema uses an explicit percentage with a nonbreaking space.
        // Accept ASCII digits plus whitespace and %, never localized display labels.
        if let text = health["sppower_battery_health_maximum_capacity"] as? String {
            let compact = text.filter { !$0.isWhitespace }
            if compact.last == "%", !compact.dropLast().isEmpty,
               compact.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }),
               let value = Double(compact.dropLast()), (0...100).contains(value) { result.maximumCapacityPercent = value }
        }
        guard result.condition != nil || result.cycles != nil || result.maximumCapacityPercent != nil else { throw ReportError.invalid }
        return result
    }
    public enum ReportError: Error { case invalid }
}
