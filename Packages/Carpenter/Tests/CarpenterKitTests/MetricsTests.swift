import CoreGraphics
import Testing

@testable import CarpenterUI

@Suite struct MetricsTests {
    @Test("A bubble's corner follows its height, in the three steps the set draws")
    func bubbleRadiusFollowsHeight() {
        #expect(CarpenterMetrics.bubbleRadius(forHeight: 32) == 9)
        #expect(CarpenterMetrics.bubbleRadius(forHeight: 52) == 14)
        #expect(CarpenterMetrics.bubbleRadius(forHeight: 200) == 20)
    }

    @Test("No step rounds a bubble into a capsule")
    func radiusNeverReachesHalfTheHeight() {
        for height in stride(from: CGFloat(28), through: 240, by: 4) {
            #expect(CarpenterMetrics.bubbleRadius(forHeight: height) < height / 2)
        }
    }

    @Test("Hit target is the platform minimum")
    func hitTargetIsFortyFour() {
        #expect(CarpenterMetrics.hitTarget == 44)
    }
}
