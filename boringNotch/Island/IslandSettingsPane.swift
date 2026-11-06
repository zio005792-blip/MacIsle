//
//  IslandSettingsPane.swift
//  boringNotch – Dynamic Island skin
//
//  Settings › 灵动岛
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct IslandSettingsPane: View {
    @ObservedObject private var settings = IslandSettings.shared
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @Default(.openNotchOnHover) private var openOnHover
    @Default(.minimumHoverDuration) private var hoverDelay
    @Default(.enableHaptics) private var haptics

    var body: some View {
        Form {
            Section("外观") {
                LabeledContent("胶囊大小") {
                    HStack {
                        Slider(value: $settings.scale, in: 0.85...1.3, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(settings.scale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("显示摄像头圆点（模仿 MacBook Pro 的开孔）", isOn: $ui.showCamera)
                Toggle("空闲时也显示小胶囊", isOn: $ui.showIdlePill)
            }
            .onChange(of: settings.scale) { _, _ in
                NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
            }

            Section("交互") {
                Toggle("鼠标悬停时自动展开", isOn: $openOnHover)
                if openOnHover {
                    LabeledContent("悬停多久展开") {
                        HStack {
                            Slider(value: $hoverDelay, in: 0.1...1.2, step: 0.05).frame(width: 180)
                            Text(String(format: "%.2f 秒", hoverDelay)).monospacedDigit().frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                LabeledContent("翻页需要滑动") {
                    HStack {
                        Slider(value: $settings.swipeCommit, in: 12...80, step: 2).frame(width: 180)
                        Text("\(Int(settings.swipeCommit)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                LabeledContent("快速轻扫至少") {
                    HStack {
                        Slider(value: $settings.swipeFlick, in: 4...40, step: 1).frame(width: 180)
                        Text("\(Int(settings.swipeFlick)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                Toggle("触控板触感反馈", isOn: $haptics)
                LabeledContent("键盘打开灵动岛") {
                    KeyboardShortcuts.Recorder(for: .toggleNotchOpen)
                }
                Text("用快捷键打开后：← → 切换卡片，数字键直接跳转，Esc 关闭并回到原来的应用。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.order) { tab in
                    HStack {
                        Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(.secondary)
                        Text(tab.title)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !settings.hiddenTabs.contains(tab) },
                            set: { settings.setHidden(tab, !$0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                .onMove { settings.move(from: $0, to: $1) }
                Button("恢复默认顺序") { settings.resetOrder() }
            } header: {
                Text("卡片（拖动排序）")
            } footer: {
                Text("音乐和 AI 任务卡片只在有内容时出现。").font(.caption).foregroundStyle(.secondary)
            }

            Section("智能") {
                Toggle("猜你想用：展开时自动翻到最可能用的卡片", isOn: $settings.predict)
                Toggle("显示猜测原因", isOn: $settings.predictHint).disabled(!settings.predict)
                Button("清除已学习的使用习惯") { IslandPredictor.shared.resetHabits() }
                Toggle("记录剪贴板历史（仅存于内存）", isOn: $clipboard.isEnabled)
            }

            IslandSelfCheckSection()
        }
        .formStyle(.grouped)
        .navigationTitle("灵动岛")
    }
}
