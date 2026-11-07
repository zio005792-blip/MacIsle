//
//  IslandSettingsPane.swift
//  MacIsle
//
//  MacIsle settings page.
//

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct IslandSettingsPane: View {
    @ObservedObject private var settings = IslandSettings.shared
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @Default(.openNotchOnHover) private var openOnHover
    @Default(.minimumHoverDuration) private var hoverDelay
    @Default(.enableHaptics) private var haptics
    @Default(.showOnAllDisplays) private var allDisplays
    @Default(.hideNotchOption) private var hideOption
    @Default(.mediaController) private var mediaSource
    @Default(.hudReplacement) private var hudReplacement
    @Default(.boringShelf) private var shelf
    @Default(.menubarIcon) private var menubarIcon
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var hudAccess = HUDAccess.shared

    var body: some View {
        Form {
            Section(tr("通用", "General")) {
                LaunchAtLogin.Toggle { Text(tr("登录时自动启动", "Launch at login")) }
                Picker(tr("界面语言", "Language"), selection: Binding(
                    get: { IslandLanguage.preference },
                    set: { IslandLanguage.apply($0) }
                )) {
                    Text(tr("跟随系统", "System")).tag(IslandLanguage.system)
                    Text("中文").tag(IslandLanguage.zh)
                    Text("English").tag(IslandLanguage.en)
                }
                Toggle(tr("在所有显示器上显示", "Show on all displays"), isOn: $allDisplays)
                    .onChange(of: allDisplays) { _, _ in
                        NotificationCenter.default.post(name: .showOnAllDisplaysChanged, object: nil)
                    }
                if !allDisplays {
                    Picker(tr("显示在", "Show on"), selection: $coordinator.preferredScreenUUID) {
                        ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                            Text(screen.localizedName).tag(screen.displayUUID)
                        }
                    }
                }
                Picker(tr("全屏应用中", "In full-screen apps"), selection: $hideOption) {
                    Text(tr("始终隐藏", "Always hide")).tag(HideNotchOption.always)
                    Text(tr("播放视频时隐藏", "Hide while playing video")).tag(HideNotchOption.nowPlayingOnly)
                    Text(tr("始终显示", "Always show")).tag(HideNotchOption.never)
                }
                Toggle(tr("菜单栏显示 MacIsle 图标", "Show MacIsle in the menu bar"), isOn: $menubarIcon)
            }

            Section(tr("外观", "Appearance")) {
                LabeledContent(tr("胶囊大小", "Pill size")) {
                    HStack {
                        Slider(value: $settings.scale, in: 0.85...1.3, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(settings.scale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle(tr("显示摄像头圆点（模仿 MacBook Pro 的开孔）", "Show camera dot (like the MacBook Pro cut-out)"), isOn: $ui.showCamera)
                Toggle(tr("空闲时也显示小胶囊", "Show the pill when idle"), isOn: $ui.showIdlePill)
            }
            .onChange(of: settings.scale) { _, _ in
                NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
            }

            Section(tr("交互", "Interaction")) {
                Toggle(tr("鼠标悬停时自动展开", "Open on hover"), isOn: $openOnHover)
                if openOnHover {
                    LabeledContent(tr("悬停多久展开", "Hover delay")) {
                        HStack {
                            Slider(value: $hoverDelay, in: 0.1...1.2, step: 0.05).frame(width: 180)
                            Text(String(format: tr("%.2f 秒", "%.2f s"), hoverDelay)).monospacedDigit().frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                LabeledContent(tr("翻页需要滑动", "Swipe to page")) {
                    HStack {
                        Slider(value: $settings.swipeCommit, in: 12...80, step: 2).frame(width: 180)
                        Text("\(Int(settings.swipeCommit)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                LabeledContent(tr("快速轻扫至少", "Minimum flick")) {
                    HStack {
                        Slider(value: $settings.swipeFlick, in: 4...40, step: 1).frame(width: 180)
                        Text("\(Int(settings.swipeFlick)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                Toggle(tr("触控板触感反馈", "Trackpad haptics"), isOn: $haptics)
                LabeledContent(tr("键盘打开灵动岛", "Open with keyboard")) {
                    KeyboardShortcuts.Recorder(for: .toggleNotchOpen)
                }
                Text(tr("用快捷键打开后：← → 切换卡片，数字键直接跳转，Esc 关闭并回到原来的应用。", "After opening with the shortcut: ← → switch cards, number keys jump, Esc closes and returns to your app."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(settings.order.enumerated()), id: \.element) { index, tab in
                    HStack {
                        Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(.secondary)
                        Text(tab.title)
                        Spacer()
                        HStack(spacing: 2) {
                            Button { settings.move(from: IndexSet(integer: index), to: index - 1) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            Button { settings.move(from: IndexSet(integer: index), to: index + 2) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == settings.order.count - 1)
                        }
                        .buttonStyle(.borderless)
                        .help(tr("调整顺序", "Reorder"))
                        Toggle("", isOn: Binding(
                            get: { !settings.hiddenTabs.contains(tab) },
                            set: { settings.setHidden(tab, !$0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                Button(tr("恢复默认顺序", "Restore Default Order")) { settings.resetOrder() }
            } header: {
                Text(tr("卡片（用 ↑ ↓ 调整顺序）", "Cards (reorder with ↑ ↓)"))
            } footer: {
                Text(tr("音乐和 AI 任务卡片只在有内容时出现。", "The Music and AI Tasks cards appear only when they have something to show.")).font(.caption).foregroundStyle(.secondary)
            }

            Section(tr("媒体与系统", "Media & System")) {
                Picker(tr("音乐信息来源", "Now Playing source"), selection: $mediaSource) {
                    ForEach(MediaControllerType.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: mediaSource) { _, _ in
                    NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
                }
                Toggle(tr("用灵动岛显示音量 / 亮度（需要辅助功能权限）", "Show volume / brightness on the island (needs Accessibility)"),
                       isOn: Binding(get: { hudAccess.isOn }, set: { hudAccess.setEnabled($0) }))
                if hudAccess.state == .waiting || hudAccess.state == .denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hudAccess.state == .waiting
                             ? tr("等待授权：在「系统设置 › 隐私与安全性 › 辅助功能」里打开 MacIsle，授权后会自动开启。",
                                  "Waiting for access: turn on MacIsle in System Settings › Privacy & Security › Accessibility — it switches on automatically.")
                             : tr("没有检测到授权。打开辅助功能设置，开启 MacIsle 后再打开这个开关。",
                                  "Access wasn't granted. Turn on MacIsle in Accessibility settings, then try again."))
                        Text(tr("如果列表里已经有 MacIsle 但仍然无效（更新版本后常见），先用「−」删掉它，再重新添加。",
                                "If MacIsle is already listed but this still doesn't work (common after updating), remove it with “−” and add it again."))
                            .foregroundStyle(.secondary)
                        Button(tr("打开辅助功能设置", "Open Accessibility Settings")) { HUDAccess.openSettings() }
                    }
                    .font(.caption)
                }
                Toggle(tr("文件暂存（拖文件到岛上）", "File shelf (drop files on the island)"), isOn: $shelf)
            }

            Section(tr("智能", "Smart")) {
                Toggle(tr("猜你想用：展开时自动翻到最可能用的卡片", "Smart pick: open on the card you most likely need"), isOn: $settings.predict)
                Toggle(tr("显示猜测原因", "Show why it was picked"), isOn: $settings.predictHint).disabled(!settings.predict)
                Button(tr("清除已学习的使用习惯", "Forget Learned Habits")) { IslandPredictor.shared.resetHabits() }
                Toggle(tr("记录剪贴板历史（仅存于内存）", "Keep clipboard history (in memory only)"), isOn: $clipboard.isEnabled)
            }

            IslandSelfCheckSection()

            Section(tr("关于", "About")) {
                LabeledContent(tr("版本", "Version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link(tr("GitHub 主页", "GitHub"), destination: URL(string: "https://github.com/zio005792-blip/MacIsle")!)
                Text(tr("MacIsle 基于开源项目 Boring Notch（GPL-3.0）修改，同样以 GPL-3.0 协议开源。", "MacIsle is a modified version of the open-source Boring Notch (GPL-3.0) and is released under GPL-3.0 as well."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
