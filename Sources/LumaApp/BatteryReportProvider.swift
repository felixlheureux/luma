import Foundation
import Darwin
import LumaCore

/// Fixed, read-only Apple report. Runs exclusively on a utility worker, with a
/// 10-second deadline and 1 MiB output ceiling. No shell or configurable arguments.
enum BatteryReportProvider {
    static func collect() throws -> BatteryPowerReport {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini", "-timeout", "8"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw BatteryPowerReport.ReportError.invalid }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 1_048_576 else { throw BatteryPowerReport.ReportError.invalid }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                // EOF does not itself guarantee that the process has exited.
                if !process.isRunning {
                    guard process.terminationStatus == 0 else { throw BatteryPowerReport.ReportError.invalid }
                    return try BatteryPowerReport.parse(data, observedAt: Date())
                }
                Thread.sleep(forTimeInterval: 0.01)
            } else if errno == EAGAIN || errno == EINTR {
                Thread.sleep(forTimeInterval: 0.01)
            } else { throw BatteryPowerReport.ReportError.invalid }
        }
        throw BatteryPowerReport.ReportError.invalid
    }
}
