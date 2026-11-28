# v0.3.04 发行说明（2026-11-28）

> 双架构（Apple Silicon / Intel）。引擎 159.0.8154.45-18（本周上游 Chromium 159 引擎更新，
> 从 .13-18 系列跨到 .45-18）。上游同步 410 commits（7c815f12 → 62ac91a0）。

## 新功能（来自上游）

- **Instant Links（即时链接）**：任意网页搜索按 ⇧↩ 直接打开第一条结果，支持一次多查询
- **5-Second Previews（五秒预览）**：Google 结果 / X / Hacker News 悬停出摘要；⇧+悬停预览任意链接
- **Ask on Page（页内提问）**：⌘F 在页面内直接向 Max 提问
- **ChatGPT in Command Bar（命令栏 ChatGPT）**：⌥⌘G 把 ⌘T 栏切到 ChatGPT（#828）
- **Enable Max 总开关**：一键全开/全关全部 Max 功能
- **MCP agents 设置**（Settings ▸ Advanced）：agent 在屏幕上的停留时长、温度等（对应后续 sidecar 方向）
- 引擎更新到 Chromium 159.0.8154.45

## 司南（fork）保持与改进

- **Max 面板重设计落地**：上游新结构 + 中国版卡片全量保留
  （模型服务商 DeepSeek/Qwen/GLM/Custom、本地模型、自动整理、用户记忆、蒸馏笔记、
  语义索引治理、模型目录、下载源），Tidy 功能行接入本地模型可用性门控
- 右键翻译/蒸馏继续走扩展桥 + 页面级 CDP（新引擎不含 fork 选择器，守卫全部就位）
- 权限提示、图标管线（司南印章 .icns）、数据目录（司南）等品牌与本地化全部保持

## 修复

- **测试隔离回归修复**：司南改名时 `CRA_DATA_DIR` 覆盖丢失，测试会读本机真实数据
  （同时影响"第二实例"功能）；已恢复
- auto-archive 计数在真实数据污染下的测试失真（同上根因）
- LZ4 测试编解码在本机 macOS 15.8 的缓冲容量问题
- 红绿灯/emoji 渲染测试对 macOS 15.8 小版本栅格化的容差
- CI：vendor 版本对齐（快照 release 制度）、ARM llama 架构钉死、Intel 交叉编译修复、
  11 个长期红的测试 harness 修复

## 发布清单（RUNBOOK §8）

- [ ] 双架构 DMG + zip + appcast + SHA256
- [ ] Gitee 同步（DMG 分卷）
- [ ] 装机冒烟：翻译四入口、蒸馏、建组命名、检查更新窗口、崩溃对话框文案
