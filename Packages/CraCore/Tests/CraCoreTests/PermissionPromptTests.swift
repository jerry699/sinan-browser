import CraCore
import Testing

/// The permission sheet's question for each kind of request.
struct PermissionPromptTests {
    let site = "https://www.messenger.com/"

    @Test func notificationsAskToShowNotifications() {
        #expect(PermissionPrompt.message(origin: site, kinds: 8) == "https://www.messenger.com/ 想要显示通知")
    }

    @Test func devicesAreUsed() {
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 2) == "https://www.messenger.com/ 想要使用你的摄像头 和 麦克风")
        #expect(PermissionPrompt.message(origin: site, kinds: 4) == "https://www.messenger.com/ 想要使用你的位置")
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 2 | 4) == "https://www.messenger.com/ 想要使用你的摄像头、麦克风 和 位置")
    }

    @Test func devicesAndNotificationsTogether() {
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 8) == "https://www.messenger.com/ 想要使用你的摄像头 和 显示通知")
    }

    // #137: Calendar's sheet said "is asking for a browser permission" for a type CraCEF
    // didn't map. Every type CraCEF maps is named.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137")) func chromesOtherTypesAreNamed() {
        let calendar = "https://calendar.google.com/"
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 18) == "https://calendar.google.com/ 想要打开某类链接，如邮件或日历链接")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 7) == "https://calendar.google.com/ 想要访问本地网络中的其他设备")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 6) == "https://calendar.google.com/ 想要管理所有显示器上的窗口")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 5 | 8 | 2) == "https://calendar.google.com/ 想要使用你的麦克风、显示通知 和 查看复制到剪贴板的文字和图片")
        for request in PermissionPrompt.requests {
            #expect(!PermissionPrompt.message(origin: calendar, kinds: request.kind).contains("browser permission"))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137")) func eachTypeHasItsOwnBit() {
        let bits = PermissionPrompt.requests.map(\.kind)
        #expect(Set(bits).count == bits.count)
        #expect(bits.allSatisfy { $0.nonzeroBitCount == 1 && $0 & (1 | 2 | 4 | 16) == 0 })
    }

    @Test func anythingElseIsAGenericPermission() {
        #expect(PermissionPrompt.message(origin: site, kinds: 16) == "https://www.messenger.com/ 正在请求浏览器权限")
        #expect(PermissionPrompt.message(origin: site, kinds: 0) == "https://www.messenger.com/ 正在请求浏览器权限")
        #expect(PermissionPrompt.message(origin: site, kinds: 8 | 16) == "https://www.messenger.com/ 想要显示通知 和 使用其他浏览器权限")
    }
}
