import CraCore
import Foundation
import Testing

/// W5 引擎：重复收藏检测 + URL 规范化。
struct W5OrganizerTests {
    @Test func normalizedURLStripsTrackersAndFragments() {
        #expect(W5Organizer.normalizedURL("https://Example.com/a/") == "https://example.com/a")
        #expect(W5Organizer.normalizedURL("http://example.com/a") == "http://example.com/a")  // scheme 保留，标候选重复
        #expect(W5Organizer.normalizedURL("https://example.com/a?utm_source=x&id=9#top") == "https://example.com/a?id=9")
        #expect(W5Organizer.normalizedURL("https://example.com") == "https://example.com/")
        #expect(W5Organizer.normalizedURL("不是链接") == nil)
    }

    @Test func duplicatesGroupsOnlyMultiples() {
        let id = { UUID() }
        let a1 = id(), a2 = id(), b1 = id(), solo = id(), bad = id()
        let groups = W5Organizer.duplicates(in: [
            (a1, "https://example.com/a"),
            (a2, "https://example.com/a/"),          // 尾斜杠差异 = 同一条
            (b1, "https://example.com/b?utm_source=x"),
            (solo, "https://unique.example/"),
            (bad, "不是链接"),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].contains(a1) && groups[0].contains(a2))
        #expect(!groups[0].contains(b1))
    }

    @Test func noDuplicatesReturnsEmpty() {
        let groups = W5Organizer.duplicates(in: [
            (UUID(), "https://a.example/"),
            (UUID(), "https://b.example/"),
        ])
        #expect(groups.isEmpty)
    }
}
