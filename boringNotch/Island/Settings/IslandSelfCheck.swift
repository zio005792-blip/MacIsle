//
//  IslandSelfCheck.swift
//  MacIsle
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
            add(await checkLocalAI())
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
        guard let w = windows.first else { return .init(name: tr("灵动岛窗口", "Island window"), status: .fail, detail: tr("没有找到窗口，请重启应用", "Window not found — please restart the app")) }
        let screen = w.screen?.localizedName ?? tr("未知屏幕", "unknown display")
        return .init(name: tr("灵动岛窗口", "Island window"), status: w.alphaValue > 0 ? .ok : .warn,
                     detail: w.alphaValue > 0 ? tr("显示在「\(screen)」", "Showing on “\(screen)”") : tr("窗口被隐藏（可能在全屏应用中）", "Window hidden (probably a full-screen app)"))
    }

    private func checkURLScheme() -> SelfCheckItem {
        guard let url = URL(string: "macisle://agent"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return .init(name: tr("AI 任务通道", "AI task channel"), status: .fail, detail: tr("macisle:// 没有注册，重新安装应用即可", "macisle:// isn't registered — reinstall the app"))
        }
        let mine = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let theirs = handler.resolvingSymlinksInPath().path
        if mine == theirs { return .init(name: tr("AI 任务通道", "AI task channel"), status: .ok, detail: tr("macisle:// 指向当前应用", "macisle:// points to this app")) }
        return .init(name: tr("AI 任务通道", "AI task channel"), status: .warn,
                     detail: tr("链接会被发给另一份副本：\(theirs)。删除那份或重新安装当前版本", "Links go to another copy: \(theirs). Delete it or reinstall this version"))
    }

    private func checkAgentHooks() -> SelfCheckItem {
        guard let last = AgentCenter.shared.lastEventAt else {
            return .init(name: tr("Claude / Codex / 终端接入", "Claude / Codex / terminal hooks"), status: .warn,
                         detail: tr("还没收到过事件：新开一个终端窗口运行 claude 或 codex 试试", "No events yet — run claude or codex in a new terminal window"))
        }
        let f = RelativeDateTimeFormatter()
        f.locale = IslandLanguage.locale
        return .init(name: tr("Claude / Codex / 终端接入", "Claude / Codex / terminal hooks"), status: .ok,
                     detail: tr("最近一次收到事件：\(f.localizedString(for: last, relativeTo: .now))（\(AgentCenter.shared.lastEventTool ?? "")）", "Last event: \(f.localizedString(for: last, relativeTo: .now)) (\(AgentCenter.shared.lastEventTool ?? ""))"))
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
        guard let text = result else { return .init(name: tr("OCR 识别", "OCR"), status: .fail, detail: tr("Vision 识别失败", "Vision text recognition failed")) }
        let ok = text.contains("2026") && (text.contains("灵动") || text.contains("自检"))
        return .init(name: tr("OCR 识别", "OCR"), status: ok ? .ok : .warn,
                     detail: ok ? tr("中文识别正常（\(ms) 毫秒）", "Chinese text recognised (\(ms) ms)") : tr("识别结果不完整：\(text.prefix(30))", "Incomplete result: \(text.prefix(30))"))
    }

    private func checkCalendar() -> SelfCheckItem {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .init(name: tr("日历权限", "Calendar access"), status: .ok, detail: tr("已授权，概览卡片会显示下一个日程", "Allowed — the Overview card shows your next event"))
        case .notDetermined: return .init(name: tr("日历权限", "Calendar access"), status: .warn, detail: tr("尚未授权：在概览卡片点「允许访问日历」", "Not yet allowed: click “Allow Calendar Access” on the Overview card"))
        default: return .init(name: tr("日历权限", "Calendar access"), status: .warn, detail: tr("被拒绝：系统设置 › 隐私与安全性 › 日历 里打开", "Denied — enable it in System Settings › Privacy & Security › Calendars"))
        }
    }

    private func checkAccessibility() async -> SelfCheckItem {
        let trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
        return .init(name: tr("辅助功能（音量/亮度 HUD）", "Accessibility (volume / brightness HUD)"), status: trusted ? .ok : .warn,
                     detail: trusted ? tr("已授权", "Allowed") : tr("未授权：需要替换系统音量 / 亮度提示时再开启", "Not allowed — only needed to replace the volume / brightness HUD"))
    }

    private func checkDownloads() -> SelfCheckItem {
        let downloads = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")).resolvingSymlinksInPath()
        let probe = downloads.appendingPathComponent(".island-selfcheck-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return .init(name: tr("「下载」文件夹", "Downloads folder"), status: .ok, detail: tr("可写入（截图导出、资料整理文档）", "Writable (screenshot export, dossier reports)"))
        } catch {
            return .init(name: tr("「下载」文件夹", "Downloads folder"), status: .fail, detail: tr("无法写入：\(error.localizedDescription)", "Not writable: \(error.localizedDescription)"))
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
        return .init(name: tr("双指翻页", "Two-finger paging"), status: ok ? .ok : .fail,
                     detail: ok ? tr("滑动翻页、轻碰回弹、上下滚动不误触均正常", "Swipe paging, nudge spring-back and vertical scrolling all behave correctly") : tr("手势判断异常（滑动=\(swipe) 轻碰=\(nudge) 上下=\(vertical)）", "Gesture check failed (swipe=\(swipe) nudge=\(nudge) vertical=\(vertical))"))
    }

    private func checkLocalAI() async -> SelfCheckItem {
        let ai = LocalAI.shared
        await ai.refresh()
        let name = tr("本地 AI", "Local AI")
        switch ai.status {
        case .ready, .sleeping, .loading:
            return .init(name: name, status: .ok, detail: "\(ai.modelName.isEmpty ? ai.endpoint : ai.modelName) · \(ai.status.label)")
        default:
            return .init(name: name, status: .warn,
                         detail: tr("没有连上 \(ai.endpoint)：运行 scripts/connect-local-ai.sh 启动本地模型网关",
                                    "Can't reach \(ai.endpoint): run scripts/connect-local-ai.sh to start the local model gateway"))
        }
    }

    private func checkClipboard() -> SelfCheckItem {
        let c = ClipboardHistory.shared
        return .init(name: tr("剪贴板记录", "Clipboard history"), status: c.isEnabled ? .ok : .warn,
                     detail: c.isEnabled ? tr("运行中，已记录 \(c.items.count) 条（只在内存）", "Running, \(c.items.count) items (in memory only)") : tr("已关闭", "Off"))
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
        return .init(name: tr("性能", "Performance"), status: status,
                     detail: String(format: tr("最近 3 秒 CPU %.1f%% · 内存 %.0f MB", "Last 3 s CPU %.1f%% · memory %.0f MB"), cpu, mb))
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
                Button(check.isRunning ? tr("检查中…", "Checking…") : tr("运行自检", "Run Self-Check")) { check.run() }
                    .disabled(check.isRunning)
                if check.isRunning { ProgressView().controlSize(.small) }
                Spacer()
                if let last = check.lastRun {
                    Text(tr("上次：\(last.formatted(date: .omitted, time: .shortened))", "Last run: \(last.formatted(date: .omitted, time: .shortened))")).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(tr("自检", "Self-check"))
        } footer: {
            Text(tr("检查 AI 任务通道、OCR、权限、文件夹访问、手势判断和资源占用。", "Checks the AI task channel, OCR, permissions, folder access, gesture logic and resource usage.")).font(.caption).foregroundStyle(.secondary)
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
