import AppKit
import CryptoKit

/// The right-click menu items the engine path can't carry (Translate Selection, Distill
/// Media): the engine framework builds its own context menu with no hook for the fork's
/// additions, so a tiny built-in extension (Extensions/SinanMenu, loaded by --load-extension
/// with the rest) registers the two entries and reaches the running browser through Chrome's
/// native messaging — CraNativeHost writes the request as a pending file and this side
/// watches for it. The CEF path keeps its own menu items and needs none of this.
@MainActor
enum SinanMenuBridge {
    static let hostName = "com.sinan.bridge"
    static let notificationName = Notification.Name("com.sinan.nativeMessage")
    static var pendingDirectory: URL { AppPaths.supportDir.appendingPathComponent("native-messages", isDirectory: true) }

    /// Before Chromium starts (main.swift): the extension folder exists for --load-extension
    /// and the host manifest sits in the profile's NativeMessagingHosts (a plain file — the
    /// relinker keeps those).
    static func prepare() {
        let fm = FileManager.default
        let folder = ExtensionStore.directory.appendingPathComponent("SinanMenu", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // The extension ID derives from the folder's absolute path (Chromium's unpacked rule),
        // which is exactly the string --load-extension receives. Both slash variants are
        // allowed: the path the engine re-derives may differ in a trailing slash.
        let path = folder.path
        let origins = [path, path + "/"].map { "chrome-extension://\(extensionID(forPath: $0))/" }
        let manifest = """
        {"manifest_version":3,"name":"司南菜单","version":"1.0.0","description":"司南浏览器的本地 AI 右键菜单",\
        "permissions":["contextMenus","nativeMessaging"],"background":{"service_worker":"background.js"}}
        """
        let translateTitle = L10n.tr("Translate Selection")
        let distillTitle = L10n.tr("Distill Media")
        let js = """
        const HOST = "\(hostName)";
        chrome.runtime.onInstalled.addListener(() => {
          chrome.contextMenus.create({id: "sinan-translate", title: "\(translateTitle)", contexts: ["selection"]});
          chrome.contextMenus.create({id: "sinan-distill", title: "\(distillTitle)", contexts: ["page", "video", "audio"]});
        });
        chrome.contextMenus.onClicked.addListener((info, tab) => {
          const payload = info.menuItemId === "sinan-translate"
            ? {action: "translate", text: info.selectionText || "", url: info.pageUrl || ""}
            : {action: "distill", url: info.pageUrl || (tab ? tab.url : "")};
          chrome.runtime.sendNativeMessage(HOST, payload, () => void chrome.runtime.lastError);
        });
        """
        try? manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try? js.write(to: folder.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)

        let host = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CraNativeHost")
        guard fm.fileExists(atPath: host.path) else { return }
        // Chromium validates the manifest: description is required (max 72 chars).
        let hostManifest = """
        {"name":"\(hostName)","description":"司南浏览器的本地消息桥","path":"\(host.path)","type":"stdio","args":["--dir=\(AppPaths.supportDir.path)"],\
        "allowed_origins":[\(origins.map { "\"\($0)\"" }.joined(separator: ","))]}
        """
        let dir = AppPaths.chromiumCache.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? hostManifest.write(to: dir.appendingPathComponent("\(hostName).json"), atomically: true, encoding: .utf8)
        try? fm.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
    }

    /// Chromium's unpacked-extension ID: the first 32 hex characters of the SHA-256 of the
    /// folder's absolute path, with every digit mapped into a-p (0→a … f→o).
    private static func extensionID(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let mapped = hex.prefix(32).compactMap { c -> Character? in
            guard let v = c.asciiValue else { return nil }
            // Chromium's rule: hex 0-9 map to a-j, hex a-f map to k-p.
            if (0x30...0x39).contains(v) { return Character(UnicodeScalar(v - 0x30 + 0x61)) }
            if (0x61...0x66).contains(v) { return Character(UnicodeScalar(v - 0x61 + 0x6B)) }
            return nil
        }
        return String(mapped)
    }

    /// The running browser listens for the host's notification and answers each pending
    /// request on the main window's current tab.
    static func startReceiving(app: AppDelegate) {
        DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { processPending(app: app) }
        }
        // A notification can be missed (the post races the observer's registration on the
        // very first launch): a slow poll picks up orphans.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { processPending(app: app) }
        }
    }

    private static func processPending(app: AppDelegate) {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "json" {
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch json["action"] as? String {
            case "translate":
                guard let text = json["text"] as? String, !text.isEmpty else { continue }
                app.main.nativeTranslateSelection(text)
            case "distill":
                app.main.nativeDistillMedia()
            default:
                continue
            }
        }
    }
}
