import Foundation
import Darwin
import LumaCore
import SwiftUI

struct SystemSample: Sendable {
    var sampledAt: Date?
    var cpuAvailable = false
    var memoryAvailable = false
    var diskAvailable = false
    var swapAvailable = false
    var networkObservation: NetworkObservation?
    var network = NetworkActivity()
    var batteryDetails = BatteryDetails()
    var totalDisk: Int64 = 0
    var availableDisk: Int64 = 0
    var physicalMemory: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var usedMemory: Int64 = 0
    var compressedMemory: Int64 = 0
    var appMemory: Int64 = 0
    var wiredMemory: Int64 = 0
    var cachedMemory: Int64 = 0
    var availableMemory: Int64 = 0
    var swap: Int64 = 0
    var pressure = "Unavailable"
    var cpu: Double = 0
    var cpuTicks: [UInt64] = []
    var battery: Int?
    var charging = false
    var onExternalPower = false
    var processes: [ProcessSample] = []
    var processGroups: [ProcessGroup] = []
    var memoryUsagePercent: Double { Double(usedMemory) / Double(max(1, physicalMemory)) * 100 }
    var pressureTint: SwiftUI.Color {
        switch pressure {
        case "Low": Palette.mint
        case "Elevated": Palette.peach
        case "High": .red
        default: .secondary
        }
    }
    var thermal = thermalState()

    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unavailable"
        }
    }

    static func collect(previous: [UInt64] = [], includeProcesses: Bool = false, includeExtendedMonitoring: Bool = true) -> SystemSample {
        var result = SystemSample()
        result.sampledAt = Date()
        if let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            result.diskAvailable = values.volumeTotalCapacity != nil && values.volumeAvailableCapacityForImportantUsage != nil
            result.totalDisk = Int64(values.volumeTotalCapacity ?? 0)
            result.availableDisk = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if vmStatus == KERN_SUCCESS {
            result.memoryAvailable = true
            // Inactive memory includes reusable file cache; it is not all app memory.
            let memory = MemoryBreakdown(physical: result.physicalMemory, pageSize: Int64(getpagesize()),
                anonymousPages: UInt64(vm.internal_page_count), wiredPages: UInt64(vm.wire_count),
                compressedPages: UInt64(vm.compressor_page_count), purgeablePages: UInt64(vm.purgeable_count), fileBackedPages: UInt64(vm.external_page_count))
            result.usedMemory = memory.used; result.appMemory = memory.app
            result.wiredMemory = memory.wired; result.compressedMemory = memory.compressed
            result.cachedMemory = memory.cached; result.availableMemory = memory.available
        }
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            // This sysctl returns dispatch flags, not XNU's internal pressure enum.
            switch pressure {
            case Int32(DispatchSource.MemoryPressureEvent.normal.rawValue): result.pressure = "Low"
            case Int32(DispatchSource.MemoryPressureEvent.warning.rawValue): result.pressure = "Elevated"
            case Int32(DispatchSource.MemoryPressureEvent.critical.rawValue): result.pressure = "High"
            default: break
            }
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { result.swap = Int64(swap.xsu_used); result.swapAvailable = true }
        var cpu = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        if cpuStatus == KERN_SUCCESS {
            result.cpuTicks = [UInt64(cpu.cpu_ticks.0), UInt64(cpu.cpu_ticks.1), UInt64(cpu.cpu_ticks.2), UInt64(cpu.cpu_ticks.3)]
            if previous.count == 4 {
                let delta = zip(result.cpuTicks, previous).map { $0 >= $1 ? $0 - $1 : 0 }
                let total = delta.reduce(0, +)
                result.cpuAvailable = total > 0
                result.cpu = total > 0 ? Double(total - delta[2]) / Double(total) * 100 : 0
            }
        }
        if includeExtendedMonitoring {
            result.networkObservation = NetworkProvider.collect()
            result.batteryDetails = BatteryProvider.collect()
            result.battery = result.batteryDetails.charge
            result.charging = result.batteryDetails.charging == true
            result.onExternalPower = result.batteryDetails.externalPower == true
        }
        if includeProcesses {
            result.processes = readProcesses()
            result.processGroups = ProcessGrouping.group(result.processes)
        }
        return result
    }

    private static func readProcesses() -> [ProcessSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid=,pcpu=,rss=,comm="]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 4, whereSeparator: { $0.isWhitespace })
            guard parts.count == 5, let pid = Int32(parts[0]), let parent = Int32(parts[1]), let cpu = Double(parts[2]), let rss = Int64(parts[3]) else { return nil }
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
            }
            return ProcessSample(pid: pid, parentPID: parent, executable: String(parts[4]), cpu: cpu,
                                 memory: status == 0 ? Int64(usage.ri_phys_footprint) : rss * 1024, usesFootprint: status == 0, instance: status == 0 ? usage.ri_proc_start_abstime : nil, bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
        }.sorted { $0.memory > $1.memory }
    }
}
