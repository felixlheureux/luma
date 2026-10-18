import Foundation

public enum BatteryPresence: String, Sendable { case available, notPresent, unavailable }

public struct BatteryInput: Sendable {
    public var current: Int?
    public var maximum: Int?
    public var nominal: Int?
    public var design: Int?
    public var charging: Bool?
    public var externalPower: Bool?
    public var health: String?
    public var condition: String?
    public var cycles: Int?
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public init(current: Int? = nil, maximum: Int? = nil, nominal: Int? = nil, design: Int? = nil,
                charging: Bool? = nil, externalPower: Bool? = nil, health: String? = nil, condition: String? = nil,
                cycles: Int? = nil, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil) {
        self.current = current; self.maximum = maximum; self.nominal = nominal; self.design = design
        self.charging = charging; self.externalPower = externalPower; self.health = health; self.condition = condition
        self.cycles = cycles; self.minutesToEmpty = minutesToEmpty; self.minutesToFull = minutesToFull
    }
}

public struct BatteryDetails: Sendable {
    public var presence: BatteryPresence
    public var charge: Int?
    public var charging: Bool?
    public var externalPower: Bool?
    public var health: String?
    public var condition: String?
    public var maximumCapacityPercent: Double?
    public var cycles: Int?
    public var estimateMinutes: Int?
    public var estimatingFullCharge = false
    public var issue: String?
    public init(presence: BatteryPresence = .unavailable, input: BatteryInput = .init(), issue: String? = nil) {
        self.presence = presence; self.issue = issue
        guard presence == .available else { return }
        charging = input.charging; externalPower = input.externalPower
        if let current = input.current, let maximum = input.maximum, maximum > 0, current >= 0, current <= maximum {
            charge = Int((Double(current) / Double(maximum) * 100).rounded())
        }
        health = Self.text(input.health); condition = Self.text(input.condition)
        if let cycles = input.cycles, cycles >= 0 { self.cycles = cycles }
        // IOPS declares capacity units consistent within a source. Max Capacity
        // alone is usually a normalized charge scale, never a health percentage.
        // Require its separately reported nominal/design pair; omit absent data.
        if let nominal = input.nominal, let design = input.design, nominal > 0, design > 0 {
            let ratio = Double(nominal) / Double(design) * 100
            if ratio.isFinite, ratio > 0, ratio <= 200 { maximumCapacityPercent = ratio }
        }
        estimatingFullCharge = input.charging == true
        let minutes = estimatingFullCharge ? input.minutesToFull : input.externalPower == false ? input.minutesToEmpty : nil
        if let minutes, minutes > 0, minutes <= 10_080 { estimateMinutes = minutes }
    }
    public var state: String {
        switch presence {
        case .notPresent: return "No internal battery reported"
        case .unavailable: return "Battery information unavailable"
        case .available:
            if charging == true { return "Charging" }
            if externalPower == true { return charge == 100 ? "Connected to power · fully charged" : "Connected to power · not charging" }
            if externalPower == false { return "On battery power" }
            return "Power state unavailable"
        }
    }
    private static func text(_ input: String?) -> String? {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(input.prefix(128))
    }
}
