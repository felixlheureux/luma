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
        #expect(reported.charge == 80 && reported.maximumCapacityPercent == 90)
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
