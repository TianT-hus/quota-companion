import AppKit
import QuotaCore

/// One native menu shared by both windows. Tracking holds are synchronous, so
/// the animation stops before the menu enters AppKit's modal tracking loop.
@MainActor final class CompanionContextMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let model: CompanionModel
    private var tracking = false
    var willOpen: (() -> Void)?
    var didClose: (() -> Void)?
    init(model: CompanionModel) {
        self.model = model
        super.init()
        menu.delegate = self; menu.autoenablesItems = false
    }
    func prepare() -> NSMenu {
        menu.removeAllItems()
        let copy = model.copy
        for (title, symbol, action) in [
            (copy.text("今日安排", "Today's schedule"), "calendar", #selector(showDay)),
            (copy.text(model.isConnecting ? "正在刷新…" : "刷新额度", model.isConnecting ? "Refreshing…" : "Refresh quota"), "arrow.clockwise", #selector(refresh)),
            (copy.text("设置", "Settings"), "gearshape", #selector(settings))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if action == #selector(refresh) { item.isEnabled = !model.isConnecting; item.toolTip = Self.statusDescription(model, now: .now) }
            menu.addItem(item)
            if action == #selector(showDay) { menu.addItem(.separator()) }
        }
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard !tracking else { return }
        tracking = true; model.holdInteraction(true); willOpen?()
    }
    func menuDidClose(_ menu: NSMenu) {
        guard tracking else { return }
        tracking = false; model.holdInteraction(false); didClose?()
    }
    @objc private func showDay() { DispatchQueue.main.async { [weak self] in self?.model.showDay() } }
    @objc private func refresh() {
        guard !model.isConnecting else { return }
        DispatchQueue.main.async { [weak self] in self?.model.refreshNow() }
    }
    @objc private func settings() { DispatchQueue.main.async { [weak self] in self?.model.openSettings() } }
    static func statusDescription(_ model: CompanionModel, now: Date) -> String {
        if model.isConnecting { return model.copy.text("正在刷新", "Refreshing") }
        if model.snapshot.windows.isEmpty { return model.copy.text("暂无额度；右键刷新", "No quota data; right-click to refresh") }
        let age = max(0, Int(now.timeIntervalSince(model.snapshot.observedAt)))
        let prefix = model.snapshot.state == .live ? "" : model.copy.text("已断开；", "Offline; ")
        let error = model.snapshot.state == .live ? "" : model.diagnosticMessage
        return prefix + model.copy.text("\(age) 秒前更新；右键刷新", "Updated \(age)s ago; right-click to refresh") + " " + error
    }
}
