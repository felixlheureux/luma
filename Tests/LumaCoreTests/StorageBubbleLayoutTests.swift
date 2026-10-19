import Foundation
import Testing
@testable import LumaCore

@Suite("Storage circle packing") struct StorageBubbleLayoutTests {
    private func entries(_ weights: [Int64]) -> [StorageMapEntry] {
        weights.enumerated().map { .init(id: "item-\($0.offset)", name: "Item \($0.offset)", bytes: $0.element, isRemainder: false) }
    }
    @Test func proportionalCirclesStaySeparateAndInsideWideAndNarrowMaps() {
        let source = entries([900, 600, 300, 150, 80, 40, 20, 10, 5, 3, 2, 1, 77])
        for size in [CGSize(width: 420, height: 420), CGSize(width: 310, height: 330), CGSize(width: 640, height: 260), CGSize(width: 120, height: 260)] {
            let circles = StorageBubbleLayout.circles(for: source, in: size)
            #expect(Set(circles.map(\.id)) == Set(source.map(\.id)))
            let reference = circles[0].radius * circles[0].radius / 900
            for circle in circles {
                #expect(circle.radius > 0 && circle.radius.isFinite)
                #expect(CGRect(origin: .zero, size: size).contains(circle.frame))
                let bytes = source.first { $0.id == circle.id }!.bytes
                #expect(abs(circle.radius * circle.radius / Double(bytes) / reference - 1) < 1e-8)
                for other in circles where circle.id != other.id {
                    #expect(hypot(circle.center.x - other.center.x, circle.center.y - other.center.y) >= circle.radius + other.radius - 1e-7)
                }
            }
        }
    }
    @Test func tinyItemsDoNotShrinkTheDominantCircleToTheirPartitionWidth() {
        let circles = StorageBubbleLayout.circles(for: entries([1_000_000] + Array(repeating: 1, count: 12)), in: CGSize(width: 310, height: 330))
        #expect(circles.count == 13)
        #expect(circles.first!.radius * 2 > 250)
    }
    @Test func packingIsStableWhenTheSameMembersAreSortedDifferently() {
        let source = entries([100, 100, 100, 50, 30, 1])
        let size = CGSize(width: 420, height: 420)
        let first = StorageBubbleLayout.circles(for: source, in: size)
        let second = StorageBubbleLayout.circles(for: source.reversed(), in: size)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.center) == second.map(\.center))
        #expect(first.map(\.radius) == second.map(\.radius))
    }
    @Test func unknownEmptyAndExtremeSizesRemainHonestAndFinite() {
        #expect(StorageBubbleLayout.circles(for: [], in: CGSize(width: 300, height: 300)).isEmpty)
        let source = entries([Int64.max, 1, 0, -1])
        let circles = StorageBubbleLayout.circles(for: source, in: CGSize(width: 300, height: 300))
        #expect(circles.count == 2)
        #expect(circles.allSatisfy { $0.radius.isFinite && $0.center.x.isFinite && $0.center.y.isFinite })
        #expect(StorageBubbleLayout.circles(for: source, in: .zero).isEmpty)
        #expect(StorageBubbleLayout.circles(for: source, in: CGSize(width: CGFloat.infinity, height: 300)).isEmpty)
    }
}
