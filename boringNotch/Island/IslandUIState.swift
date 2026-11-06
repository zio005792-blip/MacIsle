//
//  IslandUIState.swift
//  boringNotch – Dynamic Island skin
//
//  UI-only state shared by all island windows: selected page, transient alerts.
//

import Combine
import Defaults
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case media, agents, home, timer, calendar, dossier, screens, system, clipboard, shelf

    var id: String { rawValue }

    /// Cards in swipe order. Music / AI cards only exist while they have something to show.
    @MainActor
    static func available(musicActive: Bool) -> [IslandTab] {
        let settings = IslandSettings.shared
        let hidden = settings.hiddenTabs
        let list = settings.order.filter { tab in
            guard !hidden.contains(tab) else { return false }
            switch tab {
            case .media: return musicActive
            case .agents: return !AgentCenter.shared.sessions.isEmpty
            case .shelf: return Defaults[.boringShelf]
            default: return true
            }
        }
        return list.isEmpty ? [.home] : list
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .agents: return "sparkle"
        case .dossier: return "doc.text.viewfinder"
        case .screens: return "iphone.gen3"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .system: return "gauge.with.dots.needle.67percent"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "概览"
        case .agents: return "AI 任务"
        case .dossier: return "资料整理"
        case .screens: return "商店截图"
        case .media: return "音乐"
        case .calendar: return "日程"
        case .timer: return "计时"
        case .system: return "系统"
        case .clipboard: return "剪贴板"
        case .shelf: return "文件"
        }
    }
}

@MainActor
final class IslandUIState: ObservableObject {
    static let shared = IslandUIState()

    @Published var tab: IslandTab = .home
    @Published private(set) var alert: IslandAlert?
    @Published private(set) var copiedPreview: String = ""
    /// "猜你想用" reason chip shown briefly when the island opens on a predicted card.
    @Published private(set) var hint: String?
    private var hintTask: Task<Void, Never>?

    func showHint(_ text: String?) {
        hintTask?.cancel()
        hint = text
        guard text != nil else { return }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.hint = nil }
        }
    }

    @AppStorage("island.idleStyle") var showIdlePill: Bool = true
    /// Draws a virtual camera lens like the MacBook Pro's hole-punch.
    @AppStorage("island.showCamera") var showCamera: Bool = true
    /// The island was opened from the keyboard and owns key focus (arrows / numbers / Esc).
    @Published var keyboardFocus = false

    private var alertTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let music = MusicManager.shared
        // Track-change banner: only when the title really changes during playback.
        music.$songTitle
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] title in
                Task { @MainActor in
                    guard let self, !title.isEmpty, music.isPlaying else { return }
                    self.flash(.track, duration: 3)
                }
            }
            .store(in: &cancellables)
    }

    /// Shows a transient alert, replacing any current one.
    func flash(_ alert: IslandAlert, duration: TimeInterval) {
        alertTask?.cancel()
        if case .copied(let text) = alert { copiedPreview = text }
        self.alert = alert
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.alert = nil
        }
    }

    func dismissAlert() {
        alertTask?.cancel()
        alert = nil
    }

    /// Picks a sensible page when the island opens.
    func tabForOpening(musicActive: Bool, timerActive: Bool) -> IslandTab {
        if timerActive { return .timer }
        if musicActive { return .media }
        return .home
    }
}
