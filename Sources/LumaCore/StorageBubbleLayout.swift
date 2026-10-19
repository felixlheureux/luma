import Foundation

public struct StorageBubblePlacement: Identifiable, Sendable {
    public let id: String
    public let center: CGPoint
    public let radius: CGFloat
    public var frame: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// Deterministic tangent-circle packing for the bounded primary map and remainder.
/// One uniform scale preserves area ratios; padding separates circles without
/// inflating small observations or treating their rectangular bounds as targets.
public enum StorageBubbleLayout {
    public static func circles(for entries: [StorageMapEntry], in size: CGSize) -> [StorageBubblePlacement] {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return [] }
        let values = entries.filter { $0.bytes > 0 }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        guard let largest = values.first else { return [] }
        let gap = 0.035
        struct Circle {
            let id: String
            let x: Double
            let y: Double
            let r: Double
            var bounds: CGRect { CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r) }
        }
        var packed: [Circle] = []
        var bounds = CGRect.null
        for entry in values {
            let radius = sqrt(Double(entry.bytes) / Double(largest.bytes))
            if packed.isEmpty {
                let first = Circle(id: entry.id, x: 0, y: 0, r: radius)
                packed.append(first); bounds = first.bounds
                continue
            }
            // Cardinal candidates guarantee a valid position even if roundoff
            // eliminates a tangent intersection in a degenerate input.
            var candidates: [(Double, Double)] = [(bounds.maxX + radius + gap, bounds.midY)]
            for a in packed {
                let distance = a.r + radius + gap
                candidates += [(a.x + distance, a.y), (a.x - distance, a.y), (a.x, a.y + distance), (a.x, a.y - distance)]
            }
            for i in packed.indices {
                for j in packed.indices where j > i {
                    let a = packed[i], b = packed[j]
                    let dx = b.x - a.x, dy = b.y - a.y, distance = hypot(dx, dy)
                    let ar = a.r + radius + gap, br = b.r + radius + gap
                    guard distance > 0, distance <= ar + br, distance >= abs(ar - br) else { continue }
                    let along = (ar * ar - br * br + distance * distance) / (2 * distance)
                    let height = sqrt(max(0, ar * ar - along * along))
                    let x = a.x + along * dx / distance, y = a.y + along * dy / distance
                    candidates += [(x - height * dy / distance, y + height * dx / distance),
                                   (x + height * dy / distance, y - height * dx / distance)]
                }
            }
            var best: Circle?
            var bestExtent = Double.infinity, bestArea = Double.infinity
            for (x, y) in candidates {
                guard packed.allSatisfy({ hypot(x - $0.x, y - $0.y) >= radius + $0.r + gap - 1e-10 }) else { continue }
                let candidate = Circle(id: entry.id, x: x, y: y, r: radius)
                let box = bounds.union(candidate.bounds)
                let extent = max(box.width / size.width, box.height / size.height)
                let area = box.width * box.height
                if extent < bestExtent - 1e-12 || (abs(extent - bestExtent) < 1e-12 && area < bestArea) {
                    best = candidate; bestExtent = extent; bestArea = area
                }
            }
            if let best { packed.append(best); bounds = bounds.union(best.bounds) }
        }
        let inset = min(8, min(size.width, size.height) / 8)
        let scale = min((size.width - 2 * inset) / bounds.width, (size.height - 2 * inset) / bounds.height)
        return packed.map {
            StorageBubblePlacement(id: $0.id,
                center: CGPoint(x: size.width / 2 + ($0.x - bounds.midX) * scale,
                                y: size.height / 2 + ($0.y - bounds.midY) * scale), radius: $0.r * scale)
        }
    }
}
