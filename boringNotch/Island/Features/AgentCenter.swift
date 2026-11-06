//
//  AgentCenter.swift
//  MacIsle
//
//  Live Activities for AI coding agents (Claude Code, Codex) and long terminal commands.
//  Hooks report in through a URL (sandbox-friendly, never steals focus):
//
//    open -g "macisle://agent?tool=claude&event=start&id=<session>&title=<project>&app=<TERM_PROGRAM>"
//
//  events: start | attention | done | error | end (silently removes)      tools: claude | codex | shell
//  optional: detail=<text>  duration=<seconds>  status=<exit code>
//

import AppKit
import Combine
import SwiftUI

enum AgentTool: String, Equatable {
    case claude, codex, shell

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .shell: return tr("终端", "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .shell: return "terminal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude clay
        case .codex: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .shell: return Color(red: 0.62, green: 0.9, blue: 0.55)
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    enum State: Equatable { case working, attention, done, failed }

    let id: String
    let tool: AgentTool
    var title: String
    var detail: String
    var state: State
    var startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var reportedDuration: TimeInterval?
    var hostApp: String?

    var isActive: Bool { state == .working || state == .attention }

    func elapsed(at date: Date = .now) -> TimeInterval {
        if let reportedDuration { return reportedDuration }
        return (endedAt ?? date).timeIntervalSince(startedAt)
    }

    var stateText: String {
        switch state {
        case .working: return tr("运行中", "Running")
        case .attention: return tr("等你确认", "Needs you")
        case .done: return tr("已完成", "Done")
        case .failed: return tr("失败", "Failed")
        }
    }
}

@MainActor
final class AgentCenter: ObservableObject {
    static let shared = AgentCenter()

    @Published private(set) var sessions: [AgentSession] = []
    /// The session the latest alert is about.
    @Published private(set) var spotlight: AgentSession?
    /// For the self-check: when / from which tool the last hook event arrived.
    private(set) var lastEventAt: Date?
    private(set) var lastEventTool: String?

    private var sweeper: AnyCancellable?

    private init() {
        // Drop stale "working" sessions (agent crashed / terminal closed) and old finished ones.
        sweeper = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] now in
            Task { @MainActor in self?.sweep(now) }
        }
    }

    var active: [AgentSession] { sessions.filter(\.isActive) }
    var needsAttention: AgentSession? { sessions.first { $0.state == .attention } }
    /// Most relevant active session for the compact island.
    var primary: AgentSession? { needsAttention ?? active.first }

    // MARK: Intake

    func handle(url: URL) {
        guard url.scheme == "macisle", url.host == "agent" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value.flatMap { $0.isEmpty ? nil : $0 } }

        let tool = AgentTool(rawValue: q("tool") ?? "") ?? .shell
        lastEventAt = .now
        lastEventTool = tool.name
        let event = q("event") ?? "done"
        let id = "\(tool.rawValue).\(q("id") ?? q("title") ?? UUID().uuidString)"
        let title = q("title") ?? tool.name
        let detail = q("detail") ?? ""
        let now = Date.now

        if event == "end" {
            sessions.removeAll { $0.id == id }
            return
        }

        var session = sessions.first { $0.id == id } ?? AgentSession(
            id: id, tool: tool, title: title, detail: detail, state: .working,
            startedAt: now, updatedAt: now, endedAt: nil, reportedDuration: nil, hostApp: q("app"))
        session.title = title
        if !detail.isEmpty { session.detail = detail }
        session.updatedAt = now
        if let app = q("app") { session.hostApp = app }

        switch event {
        case "start", "working":
            if !session.isActive {
                session.startedAt = now
                session.endedAt = nil
                session.reportedDuration = nil
            }
            session.state = .working
        case "attention":
            session.state = .attention
        case "error":
            session.state = .failed
            session.endedAt = now
        default: // done
            let failed = (q("status").flatMap(Int.init) ?? 0) != 0
            session.state = failed ? .failed : .done
            session.endedAt = now
            if let d = q("duration").flatMap(Double.init) { session.reportedDuration = d }
        }

        upsert(session)

        switch session.state {
        case .attention:
            spotlight = session
            IslandUIState.shared.flash(.agent, duration: 6)
            NSSound(named: "Tink")?.play()
        case .done, .failed:
            spotlight = session
            IslandUIState.shared.flash(.agent, duration: 4.5)
            NSSound(named: session.state == .failed ? "Basso" : "Glass")?.play()
        case .working:
            break
        }
    }

    private func upsert(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        if sessions.count > 20 { sessions.removeLast(sessions.count - 20) }
    }

    private func sweep(_ now: Date) {
        sessions.removeAll { s in
            // A running Claude task reports at least once a minute while it works; silence for
            // 10 minutes means it was interrupted (usage limit, closed window…) without a Stop.
            (s.state == .working && s.tool == .claude && now.timeIntervalSince(s.updatedAt) > 10 * 60) ||
            (s.isActive && now.timeIntervalSince(s.updatedAt) > 3 * 3600) ||
            (!s.isActive && now.timeIntervalSince(s.endedAt ?? s.updatedAt) > 12 * 3600)
        }
    }

    // MARK: Actions

    func clearFinished() {
        sessions.removeAll { !$0.isActive }
    }

    func dismiss(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
    }

    /// Brings the terminal / app the session runs in to the front.
    func reveal(_ session: AgentSession) {
        let bundle: String
        switch session.hostApp ?? "" {
        case "Apple_Terminal": bundle = "com.apple.Terminal"
        case "iTerm.app": bundle = "com.googlecode.iterm2"
        case "vscode": bundle = "com.microsoft.VSCode"
        case "WarpTerminal": bundle = "dev.warp.Warp-Stable"
        case "ghostty": bundle = "com.mitchellh.ghostty"
        case "Xcode": bundle = "com.apple.dt.Xcode"
        case "claude-desktop", "": bundle = session.tool == .claude ? "com.anthropic.claudefordesktop" : "com.apple.Terminal"
        default: bundle = "com.apple.Terminal"
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        if session.state == .attention || !session.isActive {
            // Looking at it counts as acknowledging it.
            if !session.isActive { dismiss(session) }
        }
    }
}
