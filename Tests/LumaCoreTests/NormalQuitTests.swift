import Testing
@testable import LumaCore

struct NormalQuitTests {
    private func sample(pid: Int32 = 42, instance: UInt64? = 100, bundle: String? = "org.luma.fixture", path: String = "/Fixture.app/Contents/MacOS/Fixture") -> ProcessSample {
        .init(pid: pid, parentPID: 1, executable: path, cpu: 0, memory: 0, instance: instance, bundleIdentifier: bundle)
    }
    @Test func disappearedReusedAndRetargetedProcessesNeverReceiveQuit() {
        let captured = sample()
        for current: ProcessSample? in [nil, sample(pid: 43), sample(instance: 101), sample(instance: nil), sample(bundle: "org.other"), sample(path: "/Other.app/Contents/MacOS/Other")] {
            var called = false
            let outcome = captured.requestNormalQuit(current: current) { called = true; return true }
            #expect(outcome == .unavailable)
            #expect(!called)
        }
    }
    @Test func refusalAndAwaitingSaveRemainDistinctFromExit() {
        let captured = sample()
        #expect(captured.requestNormalQuit(current: sample(), request: { false }) == .refused)
        #expect(captured.requestNormalQuit(current: sample(), request: { true }) == .requested)
        var called = false
        #expect(sample(instance: nil).requestNormalQuit(current: sample(), request: { called = true; return true }) == .unavailable)
        #expect(!called)
    }
}
