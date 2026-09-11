import QuotaCore
import SwiftUI

struct CompanionRootView: View {
    @ObservedObject var model: CompanionModel
    @Environment(\.colorScheme) private var scheme
    var accessibility = CompanionAccessibility()
    private var appearance: BackgroundAppearance {
        (model.background?.appearances ?? .standard)[BackgroundAppearanceKey(
            dark: false, highContrast: accessibility.contrast == .increased,
            reduceTransparency: accessibility.reduceTransparency)]
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if model.isCompanionVisible && model.isExpanded {
                    TimelineView(.periodic(from: .now, by: 1)) { context in fitted(now: context.date, available: geometry.size) }
                } else { fitted(now: .now, available: geometry.size) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func fitted(now: Date, available: CGSize) -> some View {
        let scale = model.companionSize.scale
        let base = GlassDetailMetrics(windowCount: model.snapshot.windows.count).size
        let content = content(now: now).frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
        return Group {
            if available.width < base.width * scale || available.height < base.height * scale {
                ScrollView([.horizontal, .vertical]) { content }
            } else { content }
        }
    }
    private func content(now: Date) -> some View {
        HStack(spacing: 8) {
            if model.detailDirection == .left { controls(now: now) }
            card(now: now)
            if model.detailDirection != .left { controls(now: now) }
        }.foregroundStyle(appearance.text.color)
    }
    private func card(now: Date) -> some View {
        ZStack {
            GlassCardSurface(background: model.background, appearance: appearance,
                             solid: accessibility.reduceTransparency || accessibility.contrast == .increased, composition: model.customAppearance.background)
            Group {
                if model.snapshot.state == .unavailable || model.snapshot.windows.isEmpty {
                    Text(model.copy.text("暂无额度", "No quota data"))
                        .font(CompanionTokens.rounded(10, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.snapshot.windows.count > 2 {
                    ScrollView { rows(now: now) }.scrollIndicators(.hidden)
                } else { rows(now: now).frame(maxHeight: .infinity) }
            }.padding(.leading, model.detailDirection == .right ? 42 : 10)
                .padding(.trailing, model.detailDirection == .left ? 42 : 10)
                .padding(.vertical, 6)
        }.frame(width: 200, height: GlassDetailMetrics(windowCount: model.snapshot.windows.count).cardHeight)
    }
    private func controls(now: Date) -> some View {
            VStack(spacing: 4) {
                Button(action: model.openSettings) {
                    Image(systemName: "gearshape.fill").font(.system(size: 16, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(GlassControlSurface())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(model.copy.text("设置", "Settings"))
                    .help(model.copy.text("设置", "Settings"))
            Button(action: model.refreshNow) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: model.isConnecting ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 17, weight: .bold)).frame(width: 28, height: 28)
                        .background(GlassControlSurface())
                    if model.snapshot.state != .live {
                        Image(systemName: "wifi.slash").font(.system(size: 7, weight: .bold)).offset(x: 1, y: -5)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.isConnecting)
                .accessibilityLabel(model.copy.text("刷新额度", "Refresh quota"))
                .accessibilityValue(refreshDescription(now: now)).help(refreshDescription(now: now))
            }
    }
    private func rows(now: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(model.snapshot.windows.enumerated()), id: \.offset) { _, window in
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("\(window.compactLabel(locale: model.copy.locale)) \(Int(window.remainingPercent.rounded()))%")
                            .font(CompanionTokens.mono(11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 1)
                        Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                        Text(window.shortResetText(now: now, locale: model.copy.locale))
                            .font(CompanionTokens.mono(10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    LiquidProgressView(remaining: window.remainingPercent,
                        active: model.isCompanionVisible && model.isExpanded && model.snapshot.state == .live && !accessibility.reduceMotion,
                        stale: model.snapshot.state != .live, appearance: appearance, palette: model.palette, customTint: model.progressTint)
                        .frame(height: 14).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(window.accessibleLabel(locale: model.copy.locale)), \(Int(window.remainingPercent.rounded()))%, \(model.copy.text("重置倒计时", "Resets in")) \(window.shortResetText(now: now, locale: model.copy.locale))")
            }
        }
    }
    private func refreshDescription(now: Date) -> String {
        if model.isConnecting { return model.copy.text("正在刷新", "Refreshing") }
        if model.snapshot.windows.isEmpty { return model.copy.text("暂无额度，点击重试", "No quota data; retry") }
        let age = max(0, Int(now.timeIntervalSince(model.snapshot.observedAt)))
        let prefix = model.snapshot.state == .live ? "" : model.copy.text("已断开；", "Offline; ")
        let detail = model.snapshot.state == .live ? "" : model.diagnosticMessage
        return prefix + model.copy.text("\(age) 秒前更新；点击刷新", "Updated \(age)s ago; refresh") + " " + detail
    }
}
