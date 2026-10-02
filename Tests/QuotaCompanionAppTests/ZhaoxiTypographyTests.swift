import AppKit
import Testing
@testable import QuotaCompanionApp

@MainActor struct ZhaoxiTypographyTests {
    @Test func longTitleMustNotShrinkQuota() {
        let quota = [("周 100%", "09/28 22:43 重置")]
        let short = HoverTypography.size(quota: quota, schedule: ["工作"], contentWidth: 196, scale: 2, offline: false)
        let long = HoverTypography.size(quota: quota, schedule: [String(repeating: "很长的日程事项", count: 15)], contentWidth: 196, scale: 2, offline: false)
        #expect(long >= 13)
        #expect(long == short)
    }
    @Test func independentSizeHasReadableFloor() {
        for scale in [1.0, 1.5, 2.0] {
            for offline in [false, true] {
                for title in ["工作", "休息 / 工作收尾＋入睡", "洗漱＋做早餐＋检查 Kiki 的水和粮", "Prepare and review a very long work item with all details"] {
                    for quota in [[("周 100%", "09/28 22:43 重置")], [("5h 68%", "Resets 09/23 20:30"), ("周 47%", "09/28 22:43 重置")]] {
                        let size = HoverTypography.size(quota: quota, schedule: ["22:20–23:30", title], contentWidth: 98 * scale, scale: scale, offline: offline)
                        #expect(abs(size - CGFloat(max(13, 7 * scale))) < 0.001)
                        #expect(HoverTypography.secondarySize(scale: scale) >= 12)
                    }
                }
            }
        }
    }

    @Test func nativeDigitWidthsAndSharedRegularWeight() {
        let widths = (0...9).map { HoverTypography.width(String($0), size: 14) }
        #expect((widths.max()! - widths.min()!) < 0.01)
        #expect(HoverTypography.font(7).pointSize == 7)
        #expect(CompactHoverMetrics.size == CGSize(width: 150, height: 80))
    }
}
