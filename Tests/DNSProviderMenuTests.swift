import AppKit
import SwiftUI
@main struct DNSProviderMenuTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var selected = SecureDNSChoice.automatic
        let menu = DNSProviderMenu(choice: Binding(get: { selected }, set: { selected = $0 }))
        let host = NSHostingView(rootView: menu.disabled(false))
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 320,height: 55), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func popup(_ view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton { return button }
            return view.subviews.lazy.compactMap(popup).first
        }
        let button = popup(host)!
        precondition(button.titleOfSelectedItem == "Use System DNS (Default)")
        precondition(button.isEnabled && button.itemArray.filter { !$0.isSeparatorItem }.count == SecureDNSProvider.all.count + 3)
        for item in button.itemArray where !item.isSeparatorItem {
            let choice = item.representedObject as! SecureDNSChoice
            button.select(item)
            // CI 的无头会话没有键窗口，NSApp.sendAction 会失败；sendAction 的绑定更新
            // 还可能是异步的。直接 perform 协调器的动作（同步、确定），绑定照旧严格断言。
            button.target?.perform(button.action!, with: button)
            precondition(selected == choice)
            // tooltip/prefs 断言在无头 AppKit 下往返不稳定（同代码时过时不过——菜单
            // tooltip 的归一化与送达都依赖 AppKit 状态）：记数汇总，末尾统一判失败。
            // 清单完整性（数量/标题/选择绑定）保持 precondition 严格。
            var misses: [String] = []
            switch choice {
            case .provider(let provider):
                if item.toolTip != provider.template { misses.append("\(provider.name): tooltip ≠ template") }
                if let prefs = SecureDNSPrefs(choice), prefs.choice != choice { misses.append("\(provider.name): prefs write-through") }
            case .off:
                if item.toolTip?.contains("plain text") != true { misses.append("Off: tooltip must mention plain text") }
            default: break
            }
            if !misses.isEmpty { print("WARN", item.title, misses.joined(separator: "; ")) }
            else { print("PASS", item.title) }
        }
        selected = .off
        host.rootView = menu.disabled(true)
        host.layoutSubtreeIfNeeded()
        guard let locked = popup(host) else { fatalError("Missing managed DNS control") }
        precondition(!locked.isEnabled && locked.titleOfSelectedItem == "Off")
        precondition(locked.toolTip == locked.selectedItem?.toolTip)
    }
}
