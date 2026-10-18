import Foundation
import Testing
@testable import LumaCore

@Suite("Single-interface passive network activity") struct NetworkActivityTests {
    private func interface(_ name: String = "en0", id: String? = nil, received: UInt64, sent: UInt64 = 0, active: Bool = true) -> NetworkInterfaceSample {
        .init(id: id ?? name, name: name, kind: "Fixture", addresses: ["192.0.2.1"], active: active, received: received, sent: sent)
    }
    private func observation(_ time: Double, _ interfaces: [NetworkInterfaceSample], primary: String? = "en0") -> NetworkObservation {
        .init(time: time, primaryInterface: primary, interfaces: interfaces)
    }
    @Test func firstSampleAndIdleAreDifferentFromUnavailable() {
        var tracker = NetworkActivityTracker()
        let first = tracker.consume(observation(1, [interface(received: 100)]))
        #expect(first.state == .waiting && first.downloadRate == nil && first.downloaded == 0)
        let idle = tracker.consume(observation(3, [interface(received: 100)]))
        #expect(idle.state == .measuring && idle.downloadRate == 0)
        let unavailable = tracker.consume(.init(time: 4, primaryInterface: nil, interfaces: [], issue: "Permission unavailable"))
        #expect(unavailable.state == .unavailable && unavailable.downloadRate == nil)
    }
    @Test func ratesAndSessionTotalsUseOnlyMeasuredMonotonicIntervals() {
        var tracker = NetworkActivityTracker()
        _ = tracker.consume(observation(10, [interface(received: 1_000, sent: 100)]))
        let next = tracker.consume(observation(12, [interface(received: 2_000, sent: 600)]))
        #expect(next.downloadRate == 500 && next.uploadRate == 250)
        #expect(next.downloaded == 1_000 && next.uploaded == 500)
        let last = tracker.consume(observation(14, [interface(received: 2_100, sent: 700)]))
        #expect(last.downloaded == 1_100 && last.uploaded == 600)
    }
    @Test func counterResetNeverCreatesNegativeOrWrappedTraffic() {
        var tracker = NetworkActivityTracker()
        _ = tracker.consume(observation(1, [interface(received: UInt64.max - 10, sent: 900)]))
        let reset = tracker.consume(observation(3, [interface(received: 20, sent: 5)]))
        #expect(reset.state == .reset && reset.downloadRate == nil && reset.downloaded == 0)
        let next = tracker.consume(observation(5, [interface(received: 40, sent: 25)]))
        #expect(next.downloaded == 20 && next.uploaded == 20)
    }
    @Test func primaryAndExplicitInterfaceTransitionsNeverSumPhysicalAndTunnelBytes() {
        var tracker = NetworkActivityTracker()
        let before = [interface(received: 100), interface("utun4", received: 1_000)]
        let after = [interface(received: 300), interface("utun4", received: 1_200)]
        _ = tracker.consume(observation(1, before))
        let physical = tracker.consume(observation(3, after))
        #expect(physical.downloaded == 200)
        let switched = tracker.consume(observation(5, after, primary: "utun4"))
        #expect(switched.state == .waiting && switched.downloaded == 200)
        let tunnel = tracker.consume(observation(7, [interface(received: 900), interface("utun4", received: 1_600)], primary: "utun4"))
        #expect(tunnel.downloaded == 600 && tunnel.downloadRate == 200)
        let explicit = tracker.consume(observation(9, after, primary: "utun4"), selectedInterface: "en0")
        #expect(explicit.interface?.name == "en0" && explicit.downloadRate == nil)
    }
    @Test func sleepWakeAndSamplingGapsExcludeUnobservedTraffic() {
        var tracker = NetworkActivityTracker()
        _ = tracker.consume(observation(1, [interface(received: 100)]))
        let gap = tracker.consume(observation(40, [interface(received: 10_000)]))
        #expect(gap.state == .gap && gap.downloaded == 0)
        tracker.resetBaseline()
        let wake = tracker.consume(observation(42, [interface(received: 20_000)]))
        #expect(wake.state == .waiting && wake.downloaded == 0)
        #expect(tracker.consume(observation(44, [interface(received: 20_200)])).downloaded == 200)
    }
    @Test func linkLossReusedNamesAndClockAnomaliesRequireANewBaseline() {
        var tracker = NetworkActivityTracker()
        _ = tracker.consume(observation(1, [interface(received: 100)]))
        #expect(tracker.consume(observation(2, [interface(received: 500, active: false)])).state == .disconnected)
        #expect(tracker.consume(observation(3, [interface(received: 900)])).downloadRate == nil)
        #expect(tracker.consume(observation(4, [interface(id: "replacement", received: 10_000)])).downloadRate == nil)
        #expect(tracker.consume(observation(2, [interface(id: "replacement", received: 11_000)])).downloadRate == nil)
        #expect(tracker.consume(observation(.nan, [interface(received: 10)])).state == .unavailable)
    }
    @Test func missingDefaultDoesNotGuessAnActiveInterface() {
        var tracker = NetworkActivityTracker()
        let result = tracker.consume(observation(1, [interface(received: 100)], primary: nil))
        #expect(result.state == .unavailable && result.interface == nil && result.downloadRate == nil)
        let chosen = tracker.consume(observation(2, [interface(received: 200)], primary: nil), selectedInterface: "en0")
        #expect(chosen.interface?.name == "en0" && chosen.state == .waiting)
    }
}
