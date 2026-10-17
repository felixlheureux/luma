import Foundation
import Testing
@testable import LumaCore

@Suite("Memory and application monitoring") struct MonitoringTests {
    @Test func reusableFileCacheDoesNotInflateUsedMemory() {
        let memory = MemoryBreakdown(physical: 16_384, pageSize: 1, anonymousPages: 6000, wiredPages: 2000, compressedPages: 1000, purgeablePages: 500, fileBackedPages: 6000)
        #expect(memory.used == 8500)
        #expect(memory.app == 5500)
        #expect(memory.cached == 6500)
        #expect(memory.available == 7884)
        #expect(memory.used + memory.available == 16384)
    }
    @Test func purgeableAndTransientCountersNeverUnderflow() {
        let memory = MemoryBreakdown(physical: 100, pageSize: 1, anonymousPages: 10, wiredPages: 70, compressedPages: 50, purgeablePages: 30, fileBackedPages: 50)
        #expect(memory.app == 0)
        #expect(memory.used == 100)
        #expect(memory.cached == 0)
    }
    @Test func sixteenGiBUsesMemoryUnits() {
        #expect(formatMemory(16 * 1024 * 1024 * 1024).contains("16"))
        #expect(!formatMemory(16 * 1024 * 1024 * 1024).contains("17"))
    }
    @Test func browserHelpersGroupUnderOuterApplication() throws {
        let samples = [
            ProcessSample(pid: 100, parentPID: 1, executable: "/Applications/Zen.app/Contents/MacOS/zen", cpu: 2, memory: 100),
            ProcessSample(pid: 101, parentPID: 100, executable: "/Applications/Zen.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container", cpu: 20, memory: 300),
            ProcessSample(pid: 102, parentPID: 100, executable: "/Applications/Zen.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container", cpu: 10, memory: 200),
            ProcessSample(pid: 200, parentPID: 1, executable: "/Applications/Other.app/Contents/MacOS/Other", cpu: 1, memory: 50)
        ]
        let groups = ProcessGrouping.group(samples)
        #expect(groups.count == 2)
        let browser = try #require(groups.first { $0.bundleURL?.lastPathComponent == "Zen.app" })
        #expect(browser.processes.count == 3)
        #expect(browser.memory == 600)
        #expect(browser.cpu == 32)
        #expect(browser.mainPID == 100)
    }
    @Test func childToolsInheritApplicationOwnerAndCyclesTerminate() {
        let samples = [
            ProcessSample(pid: 1, parentPID: 0, executable: "/Applications/Editor.app/Contents/MacOS/editor", cpu: 1, memory: 1),
            ProcessSample(pid: 2, parentPID: 1, executable: "/usr/bin/git", cpu: 1, memory: 1),
            ProcessSample(pid: 3, parentPID: 4, executable: "/usr/bin/one", cpu: 1, memory: 1),
            ProcessSample(pid: 4, parentPID: 3, executable: "/usr/bin/two", cpu: 1, memory: 1)
        ]
        let groups = ProcessGrouping.group(samples)
        #expect(groups.first { $0.bundleURL?.lastPathComponent == "Editor.app" }?.processes.count == 2)
        #expect(groups.count == 3)
    }
}
