import AppKit
import SwiftUI

/// Arc's Max pane (Arc 1.171, Settings ▸ Max): one card, a row per feature with a picture in a
/// white frame, its name, what it does and a switch, and a line under the card about where the
/// data goes. Cra's features run on the Mac's own Apple Intelligence model, so that line says
/// the model sends nothing (and, with Instant Links on, that its searches go to the search engine),
/// or, while Apple Intelligence can't run, why and how to turn it on. The 中国版 cards below the
/// feature card are the fork's: an own provider, the local model and the memory they learn.
struct MaxPane: View {
    @Environment(SidebarStore.self) private var store
    private var service: TidyTabsService { TidyTabsService.shared }
    /// Max's mark in Arc's tile: Apple's, or sparkles before macOS 15.1.
    static var glyph: String { SettingsTab.max.symbol }
    private var downloader: ModelDownloader { .shared }
    @State private var pending: PendingModelAction?

    /// A download or delete the user confirmed in an alert.
    private struct PendingModelAction: Identifiable {
        enum Kind { case download, delete }
        let model: LocalModel
        let kind: Kind
        var id: String { "\(kind)-\(model.id)" }
        var title: String {
            kind == .download ? L10n.tr("Download %@?", model.name) : L10n.tr("Delete %@?", model.name)
        }
        func message(source: String) -> String {
            switch kind {
            case .download:
                return L10n.tr("%@ from %@. It runs on this Mac; nothing is sent anywhere.", MaxPane.bytes(model.bytes), source)
            case .delete:
                return L10n.tr("The %@ file is removed. Tidy turns off until a model is downloaded again.", MaxPane.bytes(model.bytes))
            }
        }
    }

    /// P5 用户记忆: what the tidy learned, viewable and clearable (数据治理 — memory must
    /// never silently accumulate). Extracted from the body: Swift 6.2 type-checks the
    /// combined expression too slowly.
    private func userMemoryRow() -> some View {
        SettingsCardRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("User memory")).font(.system(size: 13))
                let entries = memoryEntries()
                if entries.isEmpty {
                    Text("还没有学到的规则——手动归组几次就会积累。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.spaceName).font(.system(size: 11, weight: .medium))
                            ForEach(entry.rules) { rule in
                                Text("\(rule.domain) → \(rule.group)（\(rule.count) 次）")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            if entry.rules.isEmpty {
                                Text("标题记忆 \(entry.entryCount) 条，暂无域规则")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        } trailing: {
            Button(L10n.tr("Clear memory")) {
                store.clearAllMemory()
            }
            .controlSize(.small)
        }
    }

    private struct MemoryEntryView: Identifiable {
        let id: UUID
        let spaceName: String
        let rules: [TidyPreferences.DomainRule]
        let entryCount: Int
    }

    private func memoryEntries() -> [MemoryEntryView] {
        store.memoryOverview().map { entry in
            MemoryEntryView(id: entry.space.id, spaceName: entry.space.title,
                            rules: entry.domains, entryCount: entry.entries)
        }
    }

    var body: some View {
        @Bindable var store = store
        // Fork: the local model and the member's own provider also run Tidy, not just Apple
        // Intelligence — upstream's `available` alone would grey the rows out on our setups.
        let ms = service.maxStatus
        let available = ms == .available || ms == .remote
        // The local model always runs Tidy Tab Titles; its Tabs need the 2B.
        let titlesAvailable = available || ms == .local
        let tabsAvailable = available || (ms == .local && MaxLocal.canTidyTabs)
        // Downloads run locally on the 1.7B (the 0.8B can't): same gate as Tabs.
        let downloadsAvailable = available || (ms == .local && MaxLocal.canTidyTabs)
        let sourceLabel = ModelDownloader.preferredSource.label
        let features = [store.settings.tidyTabs, store.settings.tidyTabTitles, store.settings.tidyDownloads, store.settings.fiveSecondPreviews, store.settings.askOnPage, store.settings.instantLinks, store.settings.chatGPTInCommandBar]
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                MaxBanner()
                VStack(alignment: .leading, spacing: 0) {
                    SettingsBlurb(L10n.tr("Let Cra do more for you with Max, so you can do less. Power up your browsing with Apple Intelligence on this Mac and spend time on the things that matter — on or off screen."))
                        .padding(.top, 20)
                    // Arc's "Enable Max" with its button: Turn On All / Turn On Max / Turn Off Max, by how many are on.
                    SettingsCard {
                        SettingsCardRow {
                            HStack(spacing: 10) {
                                Image(systemName: MaxPane.glyph).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color(.sRGB, red: 0.22, green: 0.24, blue: 1)))
                                Text(L10n.tr("Enable Max")).font(.system(size: 13))
                            }
                        } trailing: {
                            let on = MaxMasterSwitch.pressTurnsOn(features)
                            Button(L10n.tr(MaxMasterSwitch.title(features))) {
                                store.settings.tidyTabs = on
                                store.settings.tidyTabTitles = on
                                store.settings.tidyDownloads = on
                                store.settings.fiveSecondPreviews = on
                                store.settings.askOnPage = on
                                store.settings.instantLinks = on
                                store.settings.chatGPTInCommandBar = on
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(MaxMasterSwitch.isEmphasised(features) ? Color(.sRGB, red: 0.2, green: 0.22, blue: 0.98) : .gray)
                            .disabled(!available)
                        }
                    }
                    .padding(.top, 20)
                    SettingsFeatureCard {
                        // Arc's first Max row (MaxSettingsUnit.askOnPage), with its text.
                        SettingsSwitchRow(L10n.tr("Ask on Page"),
                                          detail: L10n.tr("Press Command + F on any page to ask a question and let Max answer it for you in seconds."),
                                          isOn: $store.settings.askOnPage, enabled: available) {
                            AskOnPagePicture()
                        }
                        SettingsCardDivider()
                        SettingsSwitchRow(L10n.tr("Tidy Tabs"),
                                          detail: Text("\(L10n.tr("Press the")) \(Image(nsImage: BroomGlyph.image).renderingMode(.template)) \(L10n.tr("icon to let your Sidebar organize itself whenever you have six or more Today Tabs."))"),
                                          isOn: $store.settings.tidyTabs, enabled: tabsAvailable) {
                            TidyTabsPicture()
                        }
                        SettingsCardDivider()
                        // Arc 1.172's order: Instant Links comes right after Tidy Tabs.
                        SettingsSwitchRow(L10n.tr(InstantLinks.settingsTitle), detail: L10n.tr(InstantLinks.settingsDetail),
                                          isOn: $store.settings.instantLinks, enabled: available) {
                            InstantLinksPicture()
                        }
                        SettingsCardDivider()
                        SettingsSwitchRow(L10n.tr("Tidy Tab Titles"),
                                          detail: L10n.tr("Have your tabs automatically renamed with tidier, shorter titles when you Pin them."),
                                          isOn: $store.settings.tidyTabTitles, enabled: titlesAvailable) {
                            TidyTabTitlesPicture()
                        }
                        SettingsCardDivider()
                        SettingsSwitchRow(L10n.tr("Tidy Downloads"),
                                          detail: L10n.tr("Keep your many files more organized with smartly renamed downloads — and make them a little easier to find later."),
                                          isOn: $store.settings.tidyDownloads, enabled: downloadsAvailable) {
                            TidyDownloadsPicture()
                        }
                        SettingsCardDivider()
                        SettingsSwitchRow(L10n.tr("5-Second Previews"),
                                          detail: L10n.tr("Instant summaries appear when you hover over links on certain websites (Google results, X and Hacker News). Or hold Shift while hovering to preview any link."),
                                          isOn: $store.settings.fiveSecondPreviews, enabled: available) {
                            FiveSecondPreviewsPicture()
                        }
                        SettingsCardDivider()
                        // Arc's last Max row (gptSiteSearchEnabled, #828). It needs no Apple Intelligence: the message goes
                        // to chatgpt.com as a page.
                        SettingsSwitchRow(L10n.tr(ChatGPTCommandBar.settingsTitle),
                                          detail: ChatGPTCommandBar.settingsDetail(shortcut: KeyBindingRegistry.shared.action(ChatGPTCommandBar.actionID)?.primary?.display),
                                          isOn: $store.settings.chatGPTInCommandBar, enabled: true) {
                            ChatGPTPicture()
                        }
                    }
                    .padding(.top, 9)
                    // ─────────────────────────────────────────────────────────────
                    // 中国版（fork）内容区开始：下面到 "Download from" 行为止的两张卡片是
                    // fork 的功能（provider/本地模型/自动整理/用户记忆/蒸馏笔记/数据治理），
                    // 上游不存在。上游若重设计 MaxPane，恢复这段 + userMemoryRow() 调用即可。
                    // 逻辑本体在 Sources/Cra/Services/{MaxLocal,MaxProvider,MediaDistill,
                    // EmbeddingService}.swift 与 ChinaFeatures.swift。
                    // ─────────────────────────────────────────────────────────────
                    MaxCard {
                        SettingsCardRow {
                            Text(L10n.tr("Model provider")).font(.system(size: 13))
                        } trailing: {
                            Picker(L10n.tr("Model provider"), selection: Binding(get: { MaxRemote.provider },
                                                                                 set: { MaxRemote.setProvider($0); service.refresh() })) {
                                Text(L10n.tr("Apple Intelligence")).tag(MaxRemote.Provider.off)
                                Text(L10n.tr("DeepSeek")).tag(MaxRemote.Provider.deepseek)
                                Text(L10n.tr("Qwen")).tag(MaxRemote.Provider.qwen)
                                Text(L10n.tr("GLM")).tag(MaxRemote.Provider.glm)
                                Text(L10n.tr("Custom")).tag(MaxRemote.Provider.custom)
                            }
                            .labelsHidden().fixedSize()
                        }
                        if MaxRemote.provider != .off {
                            SettingsCardDivider()
                            SettingsCardRow {
                                Text(L10n.tr("API address")).font(.system(size: 13))
                            } trailing: {
                                TextField("https://…", text: Binding(get: { MaxRemote.baseURL },
                                                                     set: { MaxRemote.setBaseURL($0); service.refresh() }))
                                    .textFieldStyle(.roundedBorder).frame(width: 230)
                            }
                            SettingsCardDivider()
                            SettingsCardRow {
                                Text(L10n.tr("API key")).font(.system(size: 13))
                            } trailing: {
                                SecureField("sk-…", text: Binding(get: { MaxRemote.key() ?? "" },
                                                                  set: { MaxRemote.setKey($0); service.refresh() }))
                                    .textFieldStyle(.roundedBorder).frame(width: 230)
                            }
                            SettingsCardDivider()
                            SettingsCardRow {
                                Text(L10n.tr("Model")).font(.system(size: 13))
                            } trailing: {
                                TextField("model", text: Binding(get: { MaxRemote.model },
                                                                 set: { MaxRemote.setModel($0); service.refresh() }))
                                    .textFieldStyle(.roundedBorder).frame(width: 230)
                            }
                        }
                    }
                    .padding(.bottom, 14)
                    MaxCard {
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Local model")).font(.system(size: 13))
                                Text(MaxLocal.isInstalled
                                     ? L10n.tr("Runs Tidy on this Mac; nothing is sent anywhere.")
                                     : L10n.tr("Download one to run Tidy on this Mac; nothing is sent anywhere."))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } trailing: {
                            Toggle(L10n.tr("Local model"), isOn: Binding(get: { MaxLocal.isEnabled },
                                                                set: { MaxLocal.setEnabled($0); service.refresh() }))
                                .toggleStyle(.switch).labelsHidden().disabled(!MaxLocal.isInstalled)
                        }
                        SettingsCardDivider()
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Auto-tidy Today")).font(.system(size: 13))
                                Text(L10n.tr("Runs Tidy on its own when Today fills up.")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        } trailing: {
                            Toggle(L10n.tr("Auto-tidy Today"), isOn: Binding(get: { TidyTabsService.autoTidyEnabled },
                                                                    set: { TidyTabsService.setAutoTidyEnabled($0) }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                        SettingsCardDivider()
                        userMemoryRow()
                        SettingsCardDivider()
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Distill notes")).font(.system(size: 13))
                                Text(L10n.tr("Notes from 蒸馏音视频 land here as Markdown."))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(MediaDistillService.notesDirectory.path)
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        } trailing: {
                            Button(L10n.tr("Choose…")) {
                                let picker = NSOpenPanel()
                                picker.canChooseDirectories = true
                                picker.canChooseFiles = false
                                picker.canCreateDirectories = true
                                picker.directoryURL = MediaDistillService.notesDirectory
                                picker.message = L10n.tr("Choose the folder distilled notes land in (e.g. an Obsidian vault)")
                                if picker.runModal() == .OK, let url = picker.url {
                                    UserDefaults.standard.set(url.path, forKey: "notesDirectory")
                                }
                            }
                            .controlSize(.small)
                        }
                        SettingsCardDivider()
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Local AI data")).font(.system(size: 13))
                                Text("语义索引是缓存：清除后从浏览历史自动重建（约 20 秒）。迁移电脑时备份历史与分类记忆即可，模型可重新下载。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(String(format: "语义索引 %.1f MB（%d 页）", Double(EmbeddingService.shared.indexFileSize) / 1_048_576, EmbeddingService.shared.documentCount))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        } trailing: {
                            Button("清除重建") {
                                EmbeddingService.shared.clearIndex()
                            }
                            .controlSize(.small)
                        }
                        ForEach(ModelCatalog.all) { model in
                            SettingsCardDivider()
                            SettingsCardRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name).font(.system(size: 13))
                                    Text(localModelNote(model))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } trailing: {
                                localModelAction(model)
                            }
                        }
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Download from")).font(.system(size: 13))
                                Text(L10n.tr("Both sites serve the same file; Cra checks its SHA256 before using it."))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } trailing: {
                            Picker(L10n.tr("Download from"), selection: Binding(get: { ModelDownloader.preferredSource },
                                                                                set: { ModelDownloader.preferredSource = $0 })) {
                                ForEach(ModelSource.allCases) { Text(L10n.tr($0.label)).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    MaxFooter(status: service.maxStatus, instantLinks: store.settings.instantLinks, chatGPT: store.settings.chatGPTInCommandBar) { service.openSystemSettings() }
                        .padding(.top, 14)
                }
                .padding(.horizontal, SettingsMetrics.paneInset)
                .padding(.bottom, SettingsMetrics.paneBottom)
            }
        }
        .scrollIndicators(.automatic)
        .alert(pending?.title ?? "", isPresented: Binding(get: { pending != nil },
                                                          set: { if !$0 { pending = nil } }), presenting: pending) { action in
            switch action.kind {
            case .download:
                Button(L10n.tr("Download")) { downloader.start(action.model) }
            case .delete:
                Button(L10n.tr("Delete"), role: .destructive) {
                    downloader.delete(action.model)
                    service.refresh()
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: { action in
            Text(action.message(source: sourceLabel))
        }
        // Coming back from System Settings brings Cra to the front, which reads the status again;
        // a model still downloading gets there without that.
        .task {
            CraLog.note(String(format: "Max pane: provider=%@, baseURL=%d chars, model=%d chars, key=%d chars, configured=%d",
                               MaxRemote.provider.rawValue, MaxRemote.baseURL.count, MaxRemote.model.count,
                               MaxRemote.key()?.count ?? 0, MaxRemote.isConfigured ? 1 : 0))
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func localModelNote(_ model: LocalModel) -> String {
        let features = model.capabilities.contains(.tabs)
            ? L10n.tr("Tidy Tab Titles and Tidy Tabs") : L10n.tr("Tidy Tab Titles")
        var note = "\(MaxPane.bytes(model.bytes)) · \(features)"
        if model == MaxLocal.recommendedModel { note += " · \(L10n.tr("recommended for this Mac"))" }
        if MaxLocal.isInstalled(model) { note += " · \(L10n.tr("installed"))" }
        return note
    }

    @ViewBuilder
    private func localModelAction(_ model: LocalModel) -> some View {
        if downloader.isBusy && downloader.modelID == model.id {
            HStack(spacing: 8) {
                Text(downloader.phase == .verifying
                     ? L10n.tr("Checking…")
                     : L10n.tr("%d%% · %@ of %@", Int(downloader.fraction * 100), MaxPane.bytes(downloader.received), MaxPane.bytes(downloader.total)))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L10n.tr("Cancel")) { downloader.cancel() }
                    .buttonStyle(.link)
            }
        } else if MaxLocal.isInstalled(model) {
            Button(L10n.tr("Delete…")) { pending = PendingModelAction(model: model, kind: .delete) }
                .buttonStyle(.link)
                .disabled(downloader.isBusy)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Button(L10n.tr("Download")) { pending = PendingModelAction(model: model, kind: .download) }
                    .disabled(downloader.isBusy)
                if case .failed(let message) = downloader.phase, downloader.modelID == model.id {
                    Text(message)
                        .font(.system(size: 10)).foregroundStyle(.red)
                        .frame(maxWidth: 200, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private static func bytes(_ count: Int64) -> String {
        String(format: "%.1f GB", Double(count) / Double(1 << 30))
    }
}

/// The card around the fork's Max rows: a hairline border on a lighter fill, rows split by hairlines.
struct MaxCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

/// Under the card, where Arc says Max sends data to its AI partners: what runs where, or why it
/// can't and the way to System Settings ▸ Apple Intelligence & Siri.
private struct MaxFooter: View {
    let status: TidyTabsService.MaxStatus
    let instantLinks: Bool
    let chatGPT: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text(L10n.tr(status.explanation))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // The searches Instant Links makes are the one thing that leaves the Mac.
            if status == .available, instantLinks {
                Text(L10n.tr("Instant Links sends what it searches for to your search engine, as a search would."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Arc says Max sends data to its AI partners; here only what you ask ChatGPT leaves, to its site.
            if chatGPT {
                Text(L10n.tr("ChatGPT in the Command Bar sends what you ask to chatgpt.com, as opening the page would."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status.canOpenSettings {
                Button(action: openSettings) {
                    Text(L10n.tr("Turn on Apple Intelligence in System Settings")).font(.system(size: 12)).underline()
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// ChatGPT in the Command Bar's picture: the bar scoped to ChatGPT, its pill in Arc's #75A99C and "Send a Message…".
private struct ChatGPTPicture: View {
    private let teal = Color(red: 0x75 / 255, green: 0xA9 / 255, blue: 0x9C / 255)
    var body: some View {
        ZStack {
            teal.opacity(0.85)
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(Color(white: 0.75))
                Text("ChatGPT").font(.system(size: 4.5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 3).padding(.vertical, 1.5)
                    .background(Capsule().fill(teal))
                Text("Send a Message…").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(Color(white: 0.6)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5).padding(.vertical, 5)
            .frame(width: 72)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(red: 0.18, green: 0.17, blue: 0.15)))
        }
    }
}

/// Arc's Ask on Page picture (AskOnPagePreview): a find card with its Ask button on pink.
private struct AskOnPagePicture: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.62, blue: 0.62)
            VStack(alignment: .trailing, spacing: 0) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.9))
                    .frame(width: 48, height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.85)).frame(width: 30, height: 2)
                    Spacer(minLength: 0)
                    Text("Ask").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(red: 0.22, green: 0.24, blue: 1)))
                }
                .padding(.horizontal, 4).padding(.vertical, 3)
                .frame(width: 70)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white))
                .padding(.top, 5)
            }
            .frame(width: 70)
        }
    }
}

/// Arc's Tidy Downloads picture: the "Download renamed to:" card on blue.
private struct TidyDownloadsPicture: View {
    private let grey = Color(white: 0.55)
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.20, blue: 0.93)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("Download renamed to:").font(.system(size: 4)).foregroundStyle(grey).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                    Image(systemName: "xmark").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                }
                Text("Navan Itinerary.pdf").font(.system(size: 6, weight: .medium)).foregroundStyle(.black).lineLimit(1).fixedSize()
                Text("387494875.pdf").font(.system(size: 4.5)).strikethrough().foregroundStyle(grey).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(width: 70)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
        }
    }
}

/// Arc's Tidy Tab Titles picture: a renamed tab, "Double-click to rename" under it, sparkles round
/// it, on mauve.
private struct TidyTabTitlesPicture: View {
    private let ink = Color(red: 0.42, green: 0.27, blue: 0.62)
    var body: some View {
        ZStack {
            Color(red: 0.61, green: 0.48, blue: 0.62)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.32, green: 0.12, blue: 0.36))
                    .frame(width: 8, height: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Interior Design Book").font(.system(size: 6, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(1).fixedSize()
                    Text("Double-click to rename").font(.system(size: 4.5)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white))
            ForEach(0..<9, id: \.self) { i in
                Circle().fill(Color.white.opacity(i % 2 == 0 ? 0.9 : 0.6))
                    .frame(width: i % 3 == 0 ? 1.6 : 1.1, height: i % 3 == 0 ? 1.6 : 1.1)
                    .offset(x: [-33, -20, -6, 9, 22, 34, -26, 15, 30][i], y: [-12, 13, -14, 12, -13, 10, 9, -11, -6][i])
            }
        }
    }
}

/// Arc's Tidy Tabs picture: the squiggle, the broom and a ✕ on lavender.
private struct TidyTabsPicture: View {
    private let ink = Color(red: 0.55, green: 0.52, blue: 0.72)
    var body: some View {
        ZStack {
            Color(red: 0.84, green: 0.82, blue: 0.96)
            HStack(spacing: 5) {
                Squiggle()
                    .stroke(Color(red: 0.70, green: 0.67, blue: 0.90), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .frame(width: 40, height: 5)
                Image(nsImage: BroomGlyph.image).renderingMode(.template).foregroundStyle(ink)
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(ink)
            }
            .offset(x: -2)
        }
    }
}

/// Instant Links' picture: the command bar with a search and the ⇧ and ↩ keycaps, on pink.
private struct InstantLinksPicture: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.62, blue: 0.62)
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass").font(.system(size: 5, weight: .medium)).foregroundStyle(Color(white: 0.55))
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.8)).frame(width: 20, height: 2)
                Spacer(minLength: 0)
                ForEach(["⇧", "↩"], id: \.self) { key in
                    Text(key).font(.system(size: 5.5, weight: .semibold)).foregroundStyle(Color(white: 0.35))
                        .frame(width: 8, height: 8)
                        .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(white: 0.92)))
                }
            }
            .padding(.horizontal, 5)
            .frame(width: 70, height: 16)
            .background(Capsule().fill(Color.white))
        }
    }
}

/// Arc's 5-Second Previews picture: a summary card with bullet points on teal.
private struct FiveSecondPreviewsPicture: View {
    private let grey = Color(white: 0.55)
    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.52, blue: 0.50)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "link").font(.system(size: 4)).foregroundStyle(grey)
                    Text("news.ycombinator.com").font(.system(size: 4.5, weight: .medium)).foregroundStyle(.black).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles").font(.system(size: 4)).foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.90))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Circle().fill(grey).frame(width: 1.5, height: 1.5)
                        RoundedRectangle(cornerRadius: 1).fill(grey.opacity(0.7)).frame(width: 44, height: 2)
                    }
                    HStack(spacing: 2) {
                        Circle().fill(grey).frame(width: 1.5, height: 1.5)
                        RoundedRectangle(cornerRadius: 1).fill(grey.opacity(0.7)).frame(width: 50, height: 2)
                    }
                    HStack(spacing: 2) {
                        Circle().fill(grey).frame(width: 1.5, height: 1.5)
                        RoundedRectangle(cornerRadius: 1).fill(grey.opacity(0.7)).frame(width: 34, height: 2)
                    }
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(width: 70)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
        }
    }
}

private struct Squiggle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let period: CGFloat = 9
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        var x: CGFloat = 0
        while x <= r.width {
            p.addLine(to: CGPoint(x: r.minX + x, y: r.midY + r.height / 2 * sin(2 * .pi * x / period)))
            x += 0.5
        }
        return p
    }
}

/// Arc's Max picture band (684 × ≈125, blue, some flowers, ending in a wavy edge) with Cra's mark and "Max" in the
/// middle (Victor, 12 Nov 2026), in the system's rounded face.
private struct MaxBanner: View {
    private static let blue = Color(.sRGB, red: 0.2, green: 0.235, blue: 1)
    private static let pink = Color(.sRGB, red: 1, green: 0.62, blue: 0.62)

    var body: some View {
        ZStack {
            Self.blue
            // Flowers round the edges, some cut by them, clear of the mark and the word.
            ForEach(Array([(-300, -8, 30.0), (-240, -38, 14.0), (-200, 28, 44.0), (-160, -30, 22.0), (165, 8, 20.0), (210, -30, 30.0), (275, 22, 24.0), (340, -26, 36.0)].enumerated()), id: \.offset) { _, f in
                Flower().fill(Self.pink).frame(width: f.2, height: f.2).offset(x: CGFloat(f.0), y: CGFloat(f.1))
            }
            HStack(spacing: 10) {
                BrandMark(size: 64)
                Text("Max").font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 2, y: 2)
            }
            .offset(y: -3)
        }
        .frame(height: 125)
        .clipShape(SettingsScallopedBand())
        .accessibilityHidden(true)
    }
}

/// A flower of four lobes.
private struct Flower: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) * 0.28
        for (dx, dy) in [(0.0, -0.5), (0.5, 0.0), (0.0, 0.5), (-0.5, 0.0)] {
            p.addEllipse(in: CGRect(x: rect.midX + dx * rect.width * 0.55 - r, y: rect.midY + dy * rect.height * 0.55 - r, width: r * 2, height: r * 2))
        }
        return p
    }
}
