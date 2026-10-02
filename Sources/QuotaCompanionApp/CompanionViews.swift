import QuotaCore
import SwiftUI

struct CompanionRootView: View {
    @ObservedObject var model: CompanionModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    var accessibility = CompanionAccessibility()
    var previewDate: Date? = nil
    var sampleQuotaCount: Int? = nil
    var sampleScale: CGFloat = 1
    var previewBackground: CompanionBackground? = nil
    var previewComposition: BackgroundComposition? = nil
    private var renderedBackground: CompanionBackground? { previewBackground ?? model.background }
    private var scale: CGFloat { max(2, sampleQuotaCount == nil ? model.companionSize.scale : sampleScale) }
    private var isSample: Bool { sampleQuotaCount != nil }
    private var windows: [QuotaWindow] {
        guard let count = sampleQuotaCount else { return model.snapshot.windows }
        let reset = Date(timeIntervalSince1970: 1790606580)
        let week = QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: reset)
        return count == 1 ? [week] : [QuotaWindow(kind: .primary, usedPercent: 32, windowDurationMinutes: 300, resetsAt: reset), week]
    }
    private var sampleSchedule: ScheduleBlock? { isSample ? ScheduleBlock(start: 13*60, end: 14*60, title: model.copy.text("示例：阅读与休息", "Sample: reading & rest")) : nil }
    private var offline: Bool { !isSample && model.snapshot.state != .live }
    private func pt(_ value: CGFloat) -> CGFloat { (value * scale * displayScale).rounded() / displayScale }
    private var appearance: BackgroundAppearance {
        (renderedBackground?.appearances ?? .standard)[BackgroundAppearanceKey(
            dark: false, highContrast: accessibility.contrast == .increased,
            reduceTransparency: accessibility.reduceTransparency)]
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewDate { fitted(now: previewDate, available: geometry.size) }
                else if model.isCompanionVisible && model.isExpanded {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in fitted(now: .now, available: geometry.size) }
                } else { fitted(now: .now, available: geometry.size) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func fitted(now: Date, available: CGSize) -> some View {
        let base = isSample ? CompactHoverMetrics.size : model.detailBaseSize
        let content = card(now: now).foregroundStyle(appearance.text.color)
        return Group {
            if available.width < base.width * scale || available.height < base.height * scale {
                ScrollView([.horizontal, .vertical]) { content }
            } else { content }
        }
    }
    private func card(now: Date) -> some View {
        let overlap = !isSample && (model.detailDirection == .left || model.detailDirection == .right)
        let contentWidth = pt(CompactHoverMetrics.size.width) - pt(CompactHoverMetrics.edgeInset) - pt(overlap ? CompactHoverMetrics.overlapInset : CompactHoverMetrics.edgeInset)
        let current = isSample ? sampleSchedule : model.secretary.data.current(at: now)
        let size = HoverTypography.size(quota: windows.map {
            ("\($0.compactLabel(locale: model.copy.locale)) \(Int($0.remainingPercent.rounded()))%", $0.resetTimestampText(locale: model.copy.locale))
        }, schedule: [current?.timeLabel ?? "", current?.title ?? model.copy.text("今日安排已结束", "Schedule finished")], contentWidth: contentWidth, scale: scale, offline: offline)
        return ZStack {
            CompactHoverSurface(background: renderedBackground, appearance: appearance,
                             solid: accessibility.reduceTransparency || accessibility.contrast == .increased, composition: previewComposition ?? model.customAppearance.background, renderScale: scale)
              VStack(spacing: pt(2)) {
              Group {
                if (!isSample && model.snapshot.state == .unavailable) || windows.isEmpty {
                    Text(model.copy.text("暂无额度", "No quota data"))
                        .font(Font(HoverTypography.font(size)))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if windows.count > 2 {
                    ScrollView { rows(size: size) }.scrollIndicators(.hidden)
                } else { rows(size: size).frame(maxHeight: .infinity) }
              }.frame(height: pt(CompactHoverMetrics.quotaHeight)).clipped()
                  .help(isSample ? model.copy.text("虚构示例额度", "Fictional sample quota") : CompanionContextMenu.statusDescription(model, now: now))
              Color.clear
                  .frame(height: pt(1)).accessibilityHidden(true)
              SecretarySummary(model: model, secretary: model.secretary, now: now, renderScale: scale, sharedTextSize: size, sample: sampleSchedule)
                  .frame(height: pt(CompactHoverMetrics.scheduleHeight))
              }.frame(maxWidth: .infinity)
                .padding(.leading, pt(!isSample && model.detailDirection == .right ? CompactHoverMetrics.overlapInset : CompactHoverMetrics.edgeInset))
                .padding(.trailing, pt(!isSample && model.detailDirection == .left ? CompactHoverMetrics.overlapInset : CompactHoverMetrics.edgeInset))
                .padding(.vertical, pt(CompactHoverMetrics.verticalInset))
        }.frame(width: pt(CompactHoverMetrics.size.width), height: pt(CompactHoverMetrics.size.height))
    }
    private func rows(size: CGFloat) -> some View {
        VStack(spacing: pt(2)) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                VStack(spacing: pt(1)) {
                    HStack(spacing: pt(1)) {
                        HoverText(text: "\(window.compactLabel(locale: model.copy.locale)) \(Int(window.remainingPercent.rounded()))%", size: size, weight: .semibold)
                        if offline {
                            Image(systemName: "wifi.slash").font(.system(size: pt(7))).accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                        HoverText(text: window.resetTimestampText(locale: model.copy.locale), size: HoverTypography.secondarySize(scale: scale))
                            .help(window.resetTimestampText(locale: model.copy.locale, full: true))
                    }.frame(height: pt(11))
                    LiquidProgressView(remaining: window.remainingPercent,
                        active: !isSample && model.isCompanionVisible && model.isExpanded && model.snapshot.state == .live && !accessibility.reduceMotion,
                        stale: offline, appearance: appearance, palette: model.palette, customTint: model.progressTint,
                        style: .compact, highContrast: accessibility.contrast == .increased, renderScale: scale)
                        .frame(height: pt(CompactHoverMetrics.progressHeight)).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(window.accessibleLabel(locale: model.copy.locale)), \(Int(window.remainingPercent.rounded()))%, \(window.resetTimestampText(locale: model.copy.locale, full: true))")
            }
        }
    }
}
