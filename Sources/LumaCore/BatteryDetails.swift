import Foundation

public enum BatteryEstimate: Equatable, Sendable { case minutes(Int), calculating, notApplicable, unavailable }

public enum BatteryPresence: String, Sendable { case available, notPresent, unavailable }

public struct BatteryInput: Sendable {
    public var current: Int?
    public var maximum: Int?
    public var nominal: Int?
    public var design: Int?
    public var charged: Bool?
    public var finishingCharge: Bool?
    public var charging: Bool?
    public var externalPower: Bool?
    public var health: String?
    public var condition: String?
    public var cycles: Int?
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public init(current: Int? = nil, maximum: Int? = nil, nominal: Int? = nil, design: Int? = nil,
                charging: Bool? = nil, externalPower: Bool? = nil, health: String? = nil, condition: String? = nil,
                cycles: Int? = nil, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil, charged: Bool? = nil, finishingCharge: Bool? = nil) {
        self.charged = charged; self.finishingCharge = finishingCharge
        self.current = current; self.maximum = maximum; self.nominal = nominal; self.design = design
        self.charging = charging; self.externalPower = externalPower; self.health = health; self.condition = condition
        self.cycles = cycles; self.minutesToEmpty = minutesToEmpty; self.minutesToFull = minutesToFull
    }
}

public struct BatteryDetails: Sendable {
    public var sourceIdentity: String?
    public var charged: Bool?
    public var finishingCharge: Bool?
    public var estimate: BatteryEstimate = .unavailable
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
        charged = input.charged; finishingCharge = input.finishingCharge
        charging = input.charging; externalPower = input.externalPower
        if let current = input.current, let maximum = input.maximum, maximum > 0, current >= 0, current <= maximum {
            charge = Int((Double(current) / Double(maximum) * 100).rounded())
        }
        health = Self.text(input.health); condition = Self.text(input.condition)
        if let cycles = input.cycles, cycles >= 0 { self.cycles = cycles }
        // Normalized and nominal/design capacities are not verified health units.
        estimatingFullCharge = input.charging == true
        if charged == true || (externalPower == true && charging == false) {
            estimate = .notApplicable
        } else if charging == true || (externalPower == false && charging == false) {
            let minutes = estimatingFullCharge ? input.minutesToFull : input.minutesToEmpty
            if minutes == -1 { estimate = .calculating }
            else if let minutes, (0...10_080).contains(minutes) {
                estimate = .minutes(minutes); estimateMinutes = minutes
            }
        }
    }
    public var estimateText: String {
        switch estimate {
        case .minutes(let value): return value == 0 ? "Less than a minute" : "\(value) min"
        case .calculating: return "Calculating…"
        case .notApplicable: return "Not applicable"
        case .unavailable: return "Estimate unavailable"
        }
    }

    public var state: String {
        switch presence {
        case .notPresent: return "No internal battery reported"
        case .unavailable: return "Battery information unavailable"
        case .available:
            if finishingCharge == true { return "Finishing charge" }
            if charged == true { return externalPower == true ? "Connected to power · fully charged" : "Fully charged" }
            if charging == true { return "Charging" }
            if externalPower == true { return charging == false ? "Connected to power · not charging" : "Connected to power · charging state unavailable" }
            if externalPower == false { return "On battery power" }
            return "Power state unavailable"
        }
    }
    private static func text(_ input: String?) -> String? {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(input.prefix(128))
    }
}
