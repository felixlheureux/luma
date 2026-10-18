import Foundation

public struct NetworkInterfaceSample: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: String
    public let addresses: [String]
    public let active: Bool
    public let received: UInt64
    public let sent: UInt64
    public init(id: String, name: String, kind: String, addresses: [String], active: Bool, received: UInt64, sent: UInt64) {
        self.id = id; self.name = name; self.kind = kind; self.addresses = addresses
        self.active = active; self.received = received; self.sent = sent
    }
}

public struct NetworkObservation: Sendable {
    public let time: Double
    public let primaryInterface: String?
    public let interfaces: [NetworkInterfaceSample]
    public let issue: String?
    public init(time: Double, primaryInterface: String?, interfaces: [NetworkInterfaceSample], issue: String? = nil) {
        self.time = time; self.primaryInterface = primaryInterface; self.interfaces = interfaces; self.issue = issue
    }
}

public enum NetworkActivityState: String, Sendable {
    case waiting = "Collecting a baseline", measuring = "Measured activity", reset = "Counters reset"
    case gap = "Sampling gap", disconnected = "Interface disconnected", unavailable = "Unavailable"
}

public struct NetworkActivity: Sendable {
    public var state: NetworkActivityState = .waiting
    public var interface: NetworkInterfaceSample?
    public var downloadRate: Double?
    public var uploadRate: Double?
    public var downloaded: UInt64 = 0
    public var uploaded: UInt64 = 0
    public var totalsAvailable = true
    public var detail: String?
    public init() {}
}

/// Measures exactly one interface per interval, never sums physical and tunnel
/// counters. Transition/reset/gap intervals contribute no rates or session bytes.
public struct NetworkActivityTracker: Sendable {
    private var baseline: (time: Double, interface: NetworkInterfaceSample)?
    private var downloaded: UInt64 = 0
    private var uploaded: UInt64 = 0
    private var totalsAvailable = true
    public init() {}
    public mutating func resetBaseline() { baseline = nil }
    public mutating func consume(_ observation: NetworkObservation, selectedInterface: String? = nil) -> NetworkActivity {
        var result = NetworkActivity()
        func finish(_ value: NetworkActivity) -> NetworkActivity {
            var value = value; value.downloaded = downloaded; value.uploaded = uploaded; value.totalsAvailable = totalsAvailable
            return value
        }
        guard observation.time.isFinite, observation.issue == nil else {
            baseline = nil; result.state = .unavailable; result.detail = observation.issue ?? "Monotonic sample time unavailable."
            return finish(result)
        }
        let name = selectedInterface ?? observation.primaryInterface
        guard let interface = observation.interfaces.first(where: { $0.name == name }) else {
            baseline = nil
            result.state = name == nil && !observation.interfaces.contains(where: \.active) ? .disconnected : .unavailable
            result.detail = name == nil ? "No primary interface was reported. Choose one explicitly." : "The chosen interface is absent from the current counter report."
            return finish(result)
        }
        guard interface.active else {
            baseline = nil; result.state = .disconnected; result.interface = interface
            result.detail = "The chosen interface has no active link."
            return finish(result)
        }
        result.interface = interface
        let previous = baseline
        baseline = (observation.time, interface)
        guard let previous, previous.interface.id == interface.id else { return finish(result) }
        let seconds = observation.time - previous.time
        guard seconds > 0 else { result.state = .waiting; return finish(result) }
        guard seconds <= 10 else { result.state = .gap; result.detail = "This interval was omitted after a pause or sleep. Session totals exclude unmeasured gaps."; return finish(result) }
        guard interface.received >= previous.interface.received, interface.sent >= previous.interface.sent else {
            result.state = .reset; result.detail = "The interface counters restarted. This interval was omitted."; return finish(result)
        }
        let received = interface.received - previous.interface.received, sent = interface.sent - previous.interface.sent
        let (nextReceived, receiveOverflow) = downloaded.addingReportingOverflow(received)
        let (nextSent, sendOverflow) = uploaded.addingReportingOverflow(sent)
        if receiveOverflow || sendOverflow { totalsAvailable = false }
        else { downloaded = nextReceived; uploaded = nextSent }
        result.state = .measuring
        result.downloadRate = Double(received) / seconds; result.uploadRate = Double(sent) / seconds
        return finish(result)
    }
}
