import Foundation

extension ScanReport {
    mutating func recordFailure(_ error: Error, at url: URL, category: ItemCategory, rule: String,
                                emit: ScanEmitter, missingIsExpected: Bool = false) {
        let state = GeneratedDataScanner.failureState(error)
        let coverage = ScanCoverage(ruleID: rule, title: url.lastPathComponent, path: url.path,
                                    category: category, state: state, bytes: 0, detail: error.localizedDescription)
        self.coverage.append(coverage); emit(.coverage(coverage))
        if !missingIsExpected || state != .missing {
            isComplete = false
            let message = "\(url.lastPathComponent): \(error.localizedDescription)"
            notices.append(message); emit(.notice(message))
        }
    }
    mutating func recordItem(_ item: CleanupItem, emit: ScanEmitter) {
        items.append(item); emit(.item(item))
        let coverage = ScanCoverage(ruleID: item.ruleID, title: item.name, path: item.url.path,
                                    category: item.category, state: item.bytes > 0 ? .found : .empty,
                                    bytes: item.bytes, detail: item.explanation)
        self.coverage.append(coverage); emit(.coverage(coverage))
    }
}
