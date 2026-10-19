import Foundation
import Testing
@testable import LumaCore

@Suite("Supported battery measurements") struct BatteryDetailsTests {
    @Test func missingFieldsNeverBecomeHealthyZeroCyclesOrAFullBattery() {
        let result = BatteryDetails(presence: .available)
        #expect(result.charge == nil && result.health == nil && result.condition == nil)
        #expect(result.maximumCapacityPercent == nil && result.cycles == nil && result.estimateMinutes == nil)
        #expect(result.state == "Power state unavailable")
    }
    @Test func chargeScaleIsNotBatteryHealth() {
        let result = BatteryDetails(presence: .available, input: .init(current: 80, maximum: 100))
        #expect(result.charge == 80 && result.maximumCapacityPercent == nil)
        let reported = BatteryDetails(presence: .available, input: .init(current: 3600, maximum: 4500, nominal: 4500, design: 5000))
        #expect(reported.charge == 80 && reported.maximumCapacityPercent == nil)
    }
    @Test func reportedConditionAndZeroCyclesAreRetainedOnlyWhenProvided() {
        let result = BatteryDetails(presence: .available, input: .init(health: "Good", condition: "Check Battery", cycles: 0))
        #expect(result.health == "Good" && result.condition == "Check Battery" && result.cycles == 0)
    }
    @Test func chargingAndDischargingEstimatesUseTheReportedPowerState() {
        let charging = BatteryDetails(presence: .available, input: .init(charging: true, externalPower: true, minutesToEmpty: 100, minutesToFull: 40))
        #expect(charging.estimatingFullCharge && charging.estimateMinutes == 40)
        let discharging = BatteryDetails(presence: .available, input: .init(charging: false, externalPower: false, minutesToEmpty: 100, minutesToFull: 40))
        #expect(!discharging.estimatingFullCharge && discharging.estimateMinutes == 100)
        let limited = BatteryDetails(presence: .available, input: .init(charging: false, externalPower: true, minutesToEmpty: 100, minutesToFull: 0))
        #expect(limited.estimateMinutes == nil && limited.state == "Connected to power · not charging")
    }
    @Test func invalidAndCalculatingReportsRemainUnavailable() {
        let result = BatteryDetails(presence: .available, input: .init(current: -1, maximum: 0, nominal: 100, design: 0, charging: true, health: "", cycles: -1, minutesToFull: -1))
        #expect(result.charge == nil && result.maximumCapacityPercent == nil && result.cycles == nil && result.estimateMinutes == nil && result.health == nil)
        let impossible = BatteryDetails(presence: .available, input: .init(current: 101, maximum: 100, nominal: Int.max, design: 1))
        #expect(impossible.charge == nil && impossible.maximumCapacityPercent == nil)
    }
    @Test func desktopAndUnavailableSourcesIgnoreSpuriousFields() {
        for presence in [BatteryPresence.notPresent, .unavailable] {
            let result = BatteryDetails(presence: presence, input: .init(current: 100, maximum: 100, health: "Good", cycles: 9))
            #expect(result.charge == nil && result.health == nil && result.cycles == nil && result.estimateMinutes == nil)
        }
    }
}

@Suite("Battery estimate and Power report corrections") struct BatteryPowerReportTests {
    private func report(_ health: [String: Any], count: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["SPPowerDataType": Array(repeating: ["_name": "spbattery_information", "sppower_battery_health_info": health], count: count)])
    }
    @Test func explicitPercentageAndObservationTime() throws {
        let time = Date(timeIntervalSince1970: 42)
        let value = try BatteryPowerReport.parse(report(["sppower_battery_cycle_count": 421,
            "sppower_battery_health": "Good", "sppower_battery_health_maximum_capacity": "88\u{a0}%"]), observedAt: time)
        #expect(value.cycles == 421 && value.maximumCapacityPercent == 88 && value.condition == "Good" && value.observedAt == time)
    }
    @Test func malformedAmbiguousAndUnverifiedSchemasFail() throws {
        for data in [Data(), Data("{}".utf8), try report([:], count: 0), try report(["sppower_battery_cycle_count": 42], count: 2),
                     try report(["sppower_battery_cycle_count": true]), try report(["sppower_battery_cycle_count": -1]),
                     try report(["sppower_battery_cycle_count": 1.5]), try report(["sppower_battery_health_maximum_capacity": "101%"]),
                     try report(["sppower_battery_health_maximum_capacity": "88"]), Data(repeating: 0, count: 1_048_577)] {
            #expect(throws: (any Error).self) { try BatteryPowerReport.parse(data, observedAt: Date()) }
        }
        let partial = try BatteryPowerReport.parse(report(["sppower_battery_cycle_count": 0, "sppower_battery_health_maximum_capacity": "unknown"]), observedAt: Date())
        #expect(partial.cycles == 0 && partial.maximumCapacityPercent == nil && partial.condition == nil)
    }
    @Test func estimatesRequireExplicitApplicabilityAndPreserveSignedMinutes() {
        func battery(_ input: BatteryInput) -> BatteryDetails { .init(presence: .available, input: input) }
        #expect(battery(.init(externalPower: false, minutesToEmpty: 90)).estimate == .unavailable)
        #expect(battery(.init(charging: false, externalPower: false, minutesToEmpty: -1)).estimate == .calculating)
        #expect(battery(.init(charging: true, minutesToFull: -1)).estimate == .calculating)
        #expect(battery(.init(charging: true, minutesToFull: 0)).estimate == .minutes(0))
        #expect(battery(.init(charging: false, externalPower: false, minutesToEmpty: 0)).estimateText == "Less than a minute")
        #expect(battery(.init(charging: false, externalPower: false, minutesToEmpty: -2)).estimate == .unavailable)
        #expect(battery(.init(charging: false, externalPower: true, minutesToEmpty: 60)).estimate == .notApplicable)
        #expect(battery(.init(charging: true, minutesToFull: 10_081)).estimate == .unavailable)
    }
    @Test func chargedAndFinishingAreOSFlagsAndUnknownIsPreserved() {
        let charged = BatteryDetails(presence: .available, input: .init(current: 80, maximum: 100, charging: false, externalPower: true, charged: true))
        #expect(charged.state == "Connected to power · fully charged" && charged.estimate == .notApplicable)
        let full = BatteryDetails(presence: .available, input: .init(current: 100, maximum: 100, charging: false, externalPower: true))
        #expect(full.charged == nil && full.state == "Connected to power · not charging")
        let finishing = BatteryDetails(presence: .available, input: .init(charging: true, minutesToFull: -1, finishingCharge: true))
        #expect(finishing.state == "Finishing charge" && finishing.estimate == .calculating)
    }
}
