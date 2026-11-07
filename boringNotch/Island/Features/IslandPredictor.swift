//
//  IslandPredictor.swift
//  MacIsle
//
//  "猜你想用": picks the card you most likely want when the island opens.
//
//  score(card) = context rules (what's happening right now)
//              + learned habits (which card you ended up using, per front app and time of day)
//
//  Habits are counted locally in UserDefaults and decay over time so new routines win.
//

import AppKit
import Foundation

@MainActor
final class IslandPredictor {
    static let shared = IslandPredictor()

    struct Context {
        var frontApp: String?
        var hourBucket: String
        var dragKind: DragKind
        var clipboardFresh: Bool
        var meetingSoon: Bool
    }

    enum DragKind { case none, folder, images, files }

    struct Guess {
        let tab: IslandTab
        let reason: String
        let confidence: Double
    }

    private let storeKey = "island.predictor.habits.v1"
    /// "<feature>|<tab>" → weight
    private var habits: [String: Double]
    private var openedAt: Date?
    private var openContext: Context?
    private var guessedTab: IslandTab?
    private var manualSwitch = false

    private init() {
        habits = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Double]) ?? [:]
    }

    // MARK: Context

    func currentContext() -> Context {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hour = Calendar.current.component(.hour, from: .now)
        let bucket: String
        switch hour {
        case 5..<11: bucket = "morning"
        case 11..<14: bucket = "noon"
        case 14..<19: bucket = "afternoon"
        case 19..<24: bucket = "evening"
        default: bucket = "night"
        }
        let clipFresh: Bool = {
            guard let item = ClipboardHistory.shared.items.first, Date.now.timeIntervalSince(item.date) < 45,
                  case .text(let s) = item.content else { return false }
            return !ClipboardTransforms.suggestions(for: s).isEmpty
        }()
        let meeting: Bool = {
            guard let next = UpcomingEvents.shared.next else { return false }
            let dt = next.start.timeIntervalSinceNow
            return (dt > -300 && dt < 15 * 60)
        }()
        return Context(frontApp: front, hourBucket: bucket, dragKind: Self.dragKind(), clipboardFresh: clipFresh, meetingSoon: meeting)
    }

    private static func dragKind() -> DragKind {
        let pb = NSPasteboard(name: .drag)
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            return .none
        }
        if urls.contains(where: { $0.hasDirectoryPath }) { return .folder }
        let images: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        if urls.allSatisfy({ images.contains($0.pathExtension.lowercased()) }) { return .images }
        return .files
    }

    // MARK: Guess

    func guess(available: [IslandTab], dragging: Bool) -> Guess {
        let ctx = currentContext()
        let app = ctx.frontApp ?? ""
        var score: [IslandTab: Double] = [:]
        var why: [IslandTab: String] = [:]
        func bump(_ tab: IslandTab, _ points: Double, _ reason: String) {
            guard available.contains(tab) else { return }
            score[tab, default: 0] += points
            if why[tab] == nil || points >= 3 { why[tab] = reason }
        }

        // What's happening right now.
        let agents = AgentCenter.shared
        if agents.needsAttention != nil { bump(.agents, 12, tr("有 AI 任务在等你确认", "an AI task is waiting for you")) }
        else if !agents.active.isEmpty { bump(.agents, 3, tr("AI 任务正在运行", "an AI task is running")) }

        if dragging {
            switch ctx.dragKind {
            case .folder: bump(.dossier, 14, tr("你拖来的是一个文件夹", "you're dragging a folder"))
            case .images:
                if Self.isDevApp(app) { bump(.screens, 10, tr("从开发工具拖来的截图", "screenshots from your dev tools")) }
                bump(.shelf, 8, tr("暂存这些图片", "stash these images"))
            case .files, .none: bump(.shelf, 9, tr("暂存拖来的文件", "stash the files you're dragging"))
            }
        }

        let dossier = DossierCenter.shared
        if dossier.isBusy || dossier.phase == .review { bump(.dossier, 7, dossier.isBusy ? tr("资料正在识别", "documents are being read") : tr("资料识别完成，等你核对", "the dossier is ready for review")) }
        if IslandTimer.shared.isActive { bump(.timer, 4, tr("计时进行中", "a timer is running")) }
        // Like the iPhone: while something is playing, opening the island goes to the player.
        if MusicManager.shared.isPlaying { bump(.media, 8, tr("正在播放音乐", "music is playing")) }
        if ctx.meetingSoon { bump(.home, 6, tr("会议马上开始", "a meeting starts soon")) }
        if ctx.clipboardFresh { bump(.clipboard, 5, tr("刚复制的内容可以一键转换", "what you just copied can be converted")) }

        // Front app.
        switch app {
        case "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
             "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex":
            bump(.agents, 3, tr("你在用终端 / AI 助手", "you're in a terminal / AI assistant"))
        case "com.apple.dt.Xcode", "com.apple.iphonesimulator", "com.apple.TestFlight", "com.apple.TransporterApp":
            bump(.screens, 2.5, tr("你在做 App 上架相关的事", "you're working on an App Store release"))
            bump(.agents, 1, "")
            bump(.system, 1, "")
        case "com.apple.Music", "com.spotify.client", "com.bytedance.douyin.desktop", "com.netease.163music", "com.tencent.QQMusicMac":
            bump(.media, 3, tr("你在听歌 / 看视频", "you're listening / watching"))
        case "com.apple.finder":
            bump(.shelf, 2, tr("你在整理文件", "you're organising files"))
            bump(.dossier, 2, tr("你在整理文件", "you're organising files"))
        case "com.tencent.xinWeChat", "com.tencent.qq", "com.microsoft.Word", "com.kingsoft.wpsoffice.mac", "org.libreoffice.script":
            bump(.dossier, 2, tr("你在处理客户沟通 / 文档", "you're handling client messages / docs"))
            bump(.clipboard, 2, tr("你在处理客户沟通 / 文档", "you're handling client messages / docs"))
        default:
            break
        }
        bump(.home, 1, tr("概览", "Overview"))

        // Learned habits.
        for tab in available {
            let a = habits["app:\(app)|\(tab.rawValue)"] ?? 0
            let h = habits["hour:\(ctx.hourBucket)|\(tab.rawValue)"] ?? 0
            let learned = 1.6 * log1p(a) + 0.6 * log1p(h)
            if learned > 0 {
                score[tab, default: 0] += learned
                if a >= 2, (score[tab] ?? 0) - learned < 3 { why[tab] = tr("你在这个应用里常用它", "you often use it in this app") }
            }
        }

        let ranked = score.sorted { $0.value > $1.value }
        let best = ranked.first?.key ?? available.first ?? .home
        let top = ranked.first?.value ?? 0
        let second = ranked.dropFirst().first?.value ?? 0
        let confidence = top <= 0 ? 0 : min(1, (top - second) / max(top, 1) + 0.2)
        let guess = Guess(tab: best, reason: why[best] ?? "", confidence: confidence)

        openedAt = .now
        openContext = ctx
        guessedTab = best
        manualSwitch = false
        return guess
    }

    private static func isDevApp(_ bundle: String) -> Bool {
        ["com.apple.dt.Xcode", "com.apple.iphonesimulator", "com.apple.Preview", "com.apple.finder"].contains(bundle)
    }

    // MARK: Learning

    /// The user picked a card themselves (swipe / dots) – a strong signal.
    func noteManualSwitch() { manualSwitch = true }

    /// Called when the island closes with the card the user ended on.
    func learn(finalTab: IslandTab) {
        guard let ctx = openContext, let openedAt else { return }
        let dwell = Date.now.timeIntervalSince(openedAt)
        self.openContext = nil
        guard dwell > 1.2 else { return }            // a glance, not a use
        var weight = manualSwitch ? 2.0 : (finalTab == guessedTab ? 0.6 : 1.0)
        if dwell > 6 { weight += 0.5 }

        // Gentle decay so habits follow your current routine.
        for key in habits.keys { habits[key]! *= 0.985 }
        habits = habits.filter { $0.value > 0.05 }

        if let app = ctx.frontApp { habits["app:\(app)|\(finalTab.rawValue)", default: 0] += weight }
        habits["hour:\(ctx.hourBucket)|\(finalTab.rawValue)", default: 0] += weight * 0.5
        UserDefaults.standard.set(habits, forKey: storeKey)
    }

    func resetHabits() {
        habits = [:]
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}
