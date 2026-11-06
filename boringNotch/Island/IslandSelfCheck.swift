//
//  IslandSelfCheck.swift
//  boringNotch – Dynamic Island skin
//
//  One-click diagnostics for everything that depends on the environment:
//  URL scheme routing, agent hooks, OCR, permissions, Downloads access, gestures, CPU / memory.
//

import AppKit
import EventKit
import SwiftUI

struct SelfCheckItem: Identifiable {
    enum Status { case ok, warn, fail, running }
    let id = UUID()
    let name: String
    var status: Status
    var detail: String
}

@MainActor
final class IslandSelfCheck: ObservableObject {
    static let shared = IslandSelfCheck()

    @Published private(set) var items: [SelfCheckItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastRun: Date?

    func run() {
        guard !isRunning else { return }
        isRunning = true
        items = []
        Task {
            // Measure first, before the other checks (OCR etc.) add their own load.
            let perf = await checkPerformance()
            add(checkWindow())
            add(checkURLScheme())
            add(checkAgentHooks())
            add(await checkOCR())
            add(checkCalendar())
            add(await checkAccessibility())
            add(checkDownloads())
            add(checkSwipe())
            add(checkClipboard())
            add(perf)
            isRunning = false
            lastRun = .now
        }
    }

    private func add(_ item: SelfCheckItem) {
        withAnimation(.easeOut(duration: 0.2)) { items.append(item) }
    }

    // MARK: Checks

    private func checkWindow() -> SelfCheckItem {
        let windows = NSApp.windows.compactMap { $0 as? BoringNotchSkyLightWindow }
        guard let w = windows.first else { return .init(name: "灵动岛窗口", status: .fail, detail: "没有找到窗口，请重启应用") }
        let screen = w.screen?.localizedName ?? "未知屏幕"
        return .init(name: "灵动岛窗口", status: w.alphaValue > 0 ? .ok : .warn,
                     detail: w.alphaValue > 0 ? "显示在「\(screen)」" : "窗口被隐藏（可能在全屏应用中）")
    }

    private func checkURLScheme() -> SelfCheckItem {
        guard let url = URL(string: "boringisland://agent"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return .init(name: "AI 任务通道", status: .fail, detail: "boringisland:// 没有注册，重新安装应用即可")
        }
        let mine = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let theirs = handler.resolvingSymlinksInPath().path
        if mine == theirs { return .init(name: "AI 任务通道", status: .ok, detail: "boringisland:// 指向当前应用") }
        return .init(name: "AI 任务通道", status: .warn,
                     detail: "链接会被发给另一份副本：\(theirs)。删除那份或重新安装当前版本")
    }

    private func checkAgentHooks() -> SelfCheckItem {
        guard let last = AgentCenter.shared.lastEventAt else {
            return .init(name: "Claude / Codex / 终端接入", status: .warn,
                         detail: "还没收到过事件：新开一个终端窗口运行 claude 或 codex 试试")
        }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return .init(name: "Claude / Codex / 终端接入", status: .ok,
                     detail: "最近一次收到事件：\(f.localizedString(for: last, relativeTo: .now))（\(AgentCenter.shared.lastEventTool ?? "")）")
    }

    private func checkOCR() async -> SelfCheckItem {
        let started = Date.now
        let result: String? = await Task.detached {
            let size = CGSize(width: 900, height: 160)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            ("灵动岛自检 2026" as NSString).draw(at: NSPoint(x: 40, y: 50),
                withAttributes: [.font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.black])
            image.unlockFocus()
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return try? DossierExtractor.ocr(cg)
        }.value
        let ms = Int(Date.now.timeIntervalSince(started) * 1000)
        guard let text = result else { return .init(name: "OCR 识别", status: .fail, detail: "Vision 识别失败") }
        let ok = text.contains("2026") && (text.contains("灵动") || text.contains("自检"))
        return .init(name: "OCR 识别", status: ok ? .ok : .warn,
                     detail: ok ? "中文识别正常（\(ms) 毫秒）" : "识别结果不完整：\(text.prefix(30))")
    }

    private func checkCalendar() -> SelfCheckItem {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .init(name: "日历权限", status: .ok, detail: "已授权，概览卡片会显示下一个日程")
        case .notDetermined: return .init(name: "日历权限", status: .warn, detail: "尚未授权：在概览卡片点「允许访问日历」")
        default: return .init(name: "日历权限", status: .warn, detail: "被拒绝：系统设置 › 隐私与安全性 › 日历 里打开")
        }
    }

    private func checkAccessibility() async -> SelfCheckItem {
        let trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
        return .init(name: "辅助功能（音量/亮度 HUD）", status: trusted ? .ok : .warn,
                     detail: trusted ? "已授权" : "未授权：需要替换系统音量 / 亮度提示时再开启")
    }

    private func checkDownloads() -> SelfCheckItem {
        let downloads = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")).resolvingSymlinksInPath()
        let probe = downloads.appendingPathComponent(".island-selfcheck-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return .init(name: "「下载」文件夹", status: .ok, detail: "可写入（截图导出、资料整理文档）")
        } catch {
            return .init(name: "「下载」文件夹", status: .fail, detail: "无法写入：\(error.localizedDescription)")
        }
    }

    private func checkSwipe() -> SelfCheckItem {
        func event(_ dx: Double, _ dy: Double, _ phase: Int64) -> NSEvent? {
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            return NSEvent(cgEvent: e)
        }
        func play(_ deltas: [(Double, Double)]) -> IslandSwipeTracker.Outcome {
            let t = IslandSwipeTracker()
            var last: IslandSwipeTracker.Outcome = .pass
            var all: [NSEvent] = []
            if let e = event(0, 0, 128) { all.append(e) }
            for (i, d) in deltas.enumerated() { if let e = event(d.0, d.1, i == 0 ? 1 : 2) { all.append(e) } }
            if let e = event(0, 0, 4) { all.append(e) }
            for e in all {
                let o = t.consume(e)
                if o == .next || o == .previous { last = o }
            }
            return last
        }
        // Synthetic events aren't "natural scrolling", so +dx means fingers moving left here.
        let swipe = play(Array(repeating: (8, 1), count: 8))
        let nudge = play([(3, 0), (3, 0)])
        let vertical = play(Array(repeating: (1, 9), count: 6))
        let ok = swipe == .next && nudge == .pass && vertical == .pass
        return .init(name: "双指翻页", status: ok ? .ok : .fail,
                     detail: ok ? "滑动翻页、轻碰回弹、上下滚动不误触均正常" : "手势判断异常（滑动=\(swipe) 轻碰=\(nudge) 上下=\(vertical)）")
    }

    private func checkClipboard() -> SelfCheckItem {
        let c = ClipboardHistory.shared
        return .init(name: "剪贴板记录", status: c.isEnabled ? .ok : .warn,
                     detail: c.isEnabled ? "运行中，已记录 \(c.items.count) 条（只在内存）" : "已关闭")
    }

    private func checkPerformance() async -> SelfCheckItem {
        func cpuTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let t0 = cpuTime(), w0 = Date.now
        try? await Task.sleep(for: .seconds(3))
        let cpu = (cpuTime() - t0) / Date.now.timeIntervalSince(w0) * 100

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let mb = kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
        let status: SelfCheckItem.Status = cpu < 3 && mb < 400 ? .ok : .warn
        return .init(name: "性能", status: status,
                     detail: String(format: "最近 3 秒 CPU %.1f%% · 内存 %.0f MB", cpu, mb))
    }
}

struct IslandSelfCheckSection: View {
    @ObservedObject private var check = IslandSelfCheck.shared

    var body: some View {
        Section {
            ForEach(check.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol(item.status))
                        .foregroundStyle(color(item.status))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            HStack {
                Button(check.isRunning ? "检查中…" : "运行自检") { check.run() }
                    .disabled(check.isRunning)
                if check.isRunning { ProgressView().controlSize(.small) }
                Spacer()
                if let last = check.lastRun {
                    Text("上次：\(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("自检")
        } footer: {
            Text("检查 AI 任务通道、OCR、权限、文件夹访问、手势判断和资源占用。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func symbol(_ s: SelfCheckItem.Status) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .running: return "clock"
        }
    }

    private func color(_ s: SelfCheckItem.Status) -> Color {
        switch s {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        case .running: return .secondary
        }
    }
}
