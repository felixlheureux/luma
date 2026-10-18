#if DEBUG
import SwiftUI
import LumaCore

private final class MonitoringFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var step = 0
    private var mode = 0
    func setMode(_ value: Int) { lock.lock(); mode = value; lock.unlock() }
    func collect() -> SystemSample {
        lock.lock(); defer { lock.unlock() }
        step += 1
        var result = SystemSample()
        result.sampledAt = Date(); result.cpu = 12
        result.cpuTicks = [UInt64(step), 0, UInt64(step), 0]
        result.usedMemory = 4_000_000_000; result.appMemory = 3_000_000_000
        result.wiredMemory = 500_000_000; result.compressedMemory = 500_000_000
        result.pressure = "Low"
        result.networkObservation = .init(time: Double(step * 2), primaryInterface: "en0", interfaces: [
            .init(id: "fixture-wifi", name: "en0", kind: "Wi-Fi fixture", addresses: ["192.0.2.1"], active: true, received: UInt64(step) * 100_000, sent: UInt64(step) * 40_000),
            .init(id: "fixture-tunnel", name: "utun4", kind: "Tunnel fixture", addresses: ["2001:db8::1"], active: true, received: UInt64(step) * 90_000, sent: UInt64(step) * 30_000)
        ])
        switch mode {
        case 1: result.batteryDetails = .init(presence: .notPresent)
        case 2: result.batteryDetails = .init(presence: .available, input: .init(current: 80, maximum: 100))
        default:
            result.batteryDetails = .init(presence: .available, input: .init(current: 80, maximum: 100, nominal: 90, design: 100,
                charging: false, externalPower: false, health: "Good", condition: "Fixture condition", cycles: 42, minutesToEmpty: 100))
        }
        result.battery = result.batteryDetails.charge
        result.charging = result.batteryDetails.charging == true; result.onExternalPower = result.batteryDetails.externalPower == true
        return result
    }
}

private struct MonitoringProfile: Sendable {
    var coreMedian: Double
    var extendedMedian: Double
    var extendedP95: Double
    var networkAvailable: Bool
    var interfaceCount: Int
    var batteryPresence: String
    var batteryFields: [String]
}

extension LumaAppDelegate {
    func checkMonitoringDepth(output: String) {
        Task { @MainActor in
            let model = AppModel.shared, original = AppModel.shared.monitoringCollector
            let fixture = MonitoringFixture()
            var report: [String: Any] = ["mutationInvoked": false, "activeNetworkTestInvoked": false, "personalFoldersScanned": false]
            defer { model.monitoringCollector = original; hideMonitoringMenuForCheck(); NSApp.terminate(nil) }
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(25)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(40)) }
                guard predicate() else { throw LumaError.rejected("Monitoring native check timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                model.showMainWindow?()
                try await Task.sleep(for: .milliseconds(250))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 800 && $0.frame.height > 500 }) else { throw LumaError.rejected("No main monitoring window") }
                let profile = await Task.detached(priority: .utility) { () -> MonitoringProfile in
                    var core: [Double] = [], extended: [Double] = []
                    for _ in 0..<20 {
                        var start = ContinuousClock.now
                        _ = SystemSample.collect(includeExtendedMonitoring: false)
                        var duration = start.duration(to: .now)
                        core.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
                        start = .now
                        _ = SystemSample.collect()
                        duration = start.duration(to: .now)
                        extended.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
                    }
                    let actual = SystemSample.collect()
                    let battery = actual.batteryDetails
                    let fields: [String] = [(battery.charge != nil, "charge"), (battery.health != nil, "health"), (battery.condition != nil, "condition"),
                        (battery.cycles != nil, "cycles"), (battery.maximumCapacityPercent != nil, "maximumCapacity"), (battery.estimateMinutes != nil, "estimate")].compactMap { $0.0 ? $0.1 : nil }
                    return MonitoringProfile(coreMedian: core.sorted()[10], extendedMedian: extended.sorted()[10], extendedP95: extended.sorted()[18],
                        networkAvailable: actual.networkObservation?.issue == nil, interfaceCount: actual.networkObservation?.interfaces.count ?? 0,
                        batteryPresence: battery.presence.rawValue, batteryFields: fields)
                }.value
                report["coreMedianSeconds"] = profile.coreMedian; report["extendedMedianSeconds"] = profile.extendedMedian
                report["extendedP95Seconds"] = profile.extendedP95; report["actualNetworkProviderAvailable"] = profile.networkAvailable
                report["actualInterfaceCount"] = profile.interfaceCount; report["actualBatteryPresence"] = profile.batteryPresence
                report["actualBatteryFields"] = profile.batteryFields
                model.networkTracker = NetworkActivityTracker()
                model.monitoringCollector = { _, _ in fixture.collect() }
                model.destination = .system
                try await wait { model.system.network.interface?.id == "fixture-wifi" && model.system.network.state == .measuring }
                report["singleInterfaceRate"] = model.system.network.downloadRate == 50_000 && model.system.network.uploadRate == 20_000
                report["supportedBatteryFields"] = model.system.batteryDetails.cycles == 42 && model.system.batteryDetails.maximumCapacityPercent == 90 && model.system.battery == 80
                model.monitoringFocus = "network-details"
                try await Task.sleep(for: .milliseconds(500))
                try saveScanCheckWindow(window, path: output + "-network.png")
                model.monitoringFocus = "battery-details"
                try await Task.sleep(for: .milliseconds(400))
                try saveScanCheckWindow(window, path: output + "-battery.png")
                fixture.setMode(1)
                try await wait { model.system.batteryDetails.presence == .notPresent }
                report["desktopExplicit"] = model.system.batteryDetails.charge == nil && model.system.batteryDetails.cycles == nil
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-desktop.png")
                fixture.setMode(2)
                try await wait { model.system.batteryDetails.presence == .available && model.system.batteryDetails.health == nil }
                report["unsupportedFieldsUnavailable"] = model.system.batteryDetails.cycles == nil && model.system.batteryDetails.maximumCapacityPercent == nil && model.system.batteryDetails.estimateMinutes == nil
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-unavailable.png")
                let historyCount = model.cpuHistory.count
                window.close()
                try await Task.sleep(for: .milliseconds(100))
                guard let menu = showMonitoringMenuForCheck() else { throw LumaError.rejected("No menu companion") }
                try await Task.sleep(for: .milliseconds(400))
                try saveScanCheckWindow(menu, path: output + "-menu.png")
                report["menuFitsScreen"] = menu.frame.height <= (menu.screen?.visibleFrame.height ?? 1000)
                try await Task.sleep(for: .milliseconds(2200))
                report["menuWithoutMainWindow"] = !window.isVisible && scanCheckMenuVisible() && model.cpuHistory.count > historyCount && model.system.network.downloadRate == 50_000
                report["memoryPressureDistinct"] = model.system.pressure == "Low" && model.system.usedMemory > 0
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Monitoring QA report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
