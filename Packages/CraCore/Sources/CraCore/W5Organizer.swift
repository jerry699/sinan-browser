import Foundation

/// W5 收藏整理的引擎层（纯函数 + 一个网络探针，无 UI）：重复收藏检测与死链探针。
/// 输入解耦自 SidebarItem（调用方从 favorites/pinned 容器收集 (id, url) 即可），
/// 因此可在 CraCore 单测覆盖，也给未来其它宿主复用留口。
///
/// 司南定型原则：本引擎只**检测与建议**，绝不自动移动或删除——执行永远在用户手里。
public enum W5Organizer {

    /// 规范化 URL 用于重复比较：小写 scheme/host、去尾斜杠、去跟踪参数与锚点。
    /// https 与 http 视为同站（标记为候选重复，是否清理由用户决定）。
    public static func normalizedURL(_ raw: String) -> String? {
        guard var c = URLComponents(string: raw), let host = c.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        var path = c.path.isEmpty ? "/" : c.path
        if path.hasSuffix("/") && path.count > 1 { path = String(path.dropLast()) }
        c.host = host
        c.path = path
        c.fragment = nil
        // 常见跟踪参数一次性剥掉（与 CleanURL 精神一致，保持引擎自持）
        if var items = c.queryItems, !items.isEmpty {
            let trackers = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
                            "spm", "from", "share_token", "ref", "fbclid", "gclid"]
            items.removeAll { let n = $0.name.lowercased(); return trackers.contains(n) }
            c.queryItems = items.isEmpty ? nil : items
        }
        return c.string ?? c.url?.absoluteString
    }

    /// 重复收藏分组：每组 ≥2 条规范化后相同的条目（不含单条）。返回的是输入 id。
    public static func duplicates(in urls: [(id: UUID, url: String)]) -> [[UUID]] {
        var byNormalized: [String: [UUID]] = [:]
        for (id, raw) in urls {
            guard let n = normalizedURL(raw) else { continue }
            byNormalized[n, default: []].append(id)
        }
        return byNormalized.values.filter { $0.count >= 2 }
    }

    /// 死链探针结果。
    public enum ProbeOutcome: Equatable, Sendable {
        case alive                     // 2xx/3xx
        case dead(code: Int)           // 4xx/5xx 或连接失败（-1）
    }

    /// 单条死链探测：HEAD 优先，405/501 时回落 GET（HEAD 被拒是常态）。
    /// 返回结果与最终 URL（跟随跳转后）。
    public static func probe(url: String, timeout: TimeInterval = 10) async -> (outcome: ProbeOutcome, finalURL: String?) {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased() else {
            return (.dead(code: -1), nil)
        }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = "HEAD"
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return (.dead(code: -1), url) }
            _ = data
            if [405, 501].contains(http.statusCode) {
                var get = URLRequest(url: u, timeoutInterval: timeout)
                get.httpMethod = "GET"
                get.setValue(req.value(forHTTPHeaderField: "User-Agent"), forHTTPHeaderField: "User-Agent")
                do {
                    let (_, resp2) = try await URLSession.shared.data(for: get)
                    if let h2 = resp2 as? HTTPURLResponse {
                        return (classify(h2.statusCode), h2.url?.absoluteString ?? url)
                    }
                } catch { /* 二次失败按死链处理 */ }
                return (.dead(code: -1), url)
            }
            return (classify(http.statusCode), http.url?.absoluteString ?? url)
        } catch {
            return (.dead(code: -1), url)
        }
    }

    private static func classify(_ code: Int) -> ProbeOutcome {
        if (200..<400).contains(code) { return .alive }
        return .dead(code: code)
    }
}
