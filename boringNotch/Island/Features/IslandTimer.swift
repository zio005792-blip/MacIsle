//
//  IslandTimer.swift
//  MacIsle
//
//  Countdown timer + Pomodoro that lives in the island as a Live Activity.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandTimer: ObservableObject {
    static let shared = IslandTimer()

    enum Kind: String {
        case countdown
        case focus
        case rest

        var title: String {
            switch self {
            case .countdown: return "计时器"
            case .focus: return "专注"
            case .rest: return "休息"
            }
        }

        var tint: Color {
            switch self {
            case .countdown: return Color(red: 1.0, green: 0.62, blue: 0.04)
            case .focus: return Color(red: 1.0, green: 0.36, blue: 0.32)
            case .rest: return Color(red: 0.2, green: 0.84, blue: 0.48)
            }
        }
    }

    @Published private(set) var kind: Kind = .countdown
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var duration: TimeInterval = 0
    /// Completed focus sessions today (Pomodoro).
    @Published private(set) var focusCount: Int = 0

    @AppStorage("island.pomodoro.focusMinutes") var focusMinutes: Int = 25
    @AppStorage("island.pomodoro.restMinutes") var restMinutes: Int = 5
    @AppStorage("island.pomodoro.autoContinue") var autoContinue: Bool = true

    private var ticker: AnyCancellable?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining(at: date) / duration
    }

    // MARK: Control

    func start(seconds: TimeInterval, kind: Kind = .countdown) {
        self.kind = kind
        duration = seconds
        pausedRemaining = nil
        endDate = Date.now.addingTimeInterval(seconds)
        startTicker()
    }

    func startPomodoro() {
        start(seconds: TimeInterval(focusMinutes * 60), kind: .focus)
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        ticker = nil
    }

    func resume() {
        guard let pausedRemaining else { return }
        endDate = Date.now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        startTicker()
    }

    func toggle() {
        isRunning ? pause() : resume()
    }

    func add(seconds: TimeInterval) {
        duration += seconds
        if let endDate {
            self.endDate = endDate.addingTimeInterval(seconds)
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + seconds
        }
    }

    func cancel() {
        endDate = nil
        pausedRemaining = nil
        duration = 0
        ticker = nil
    }

    // MARK: Internals

    private func startTicker() {
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.checkFinished() }
            }
    }

    private func checkFinished() {
        guard let endDate, endDate <= .now else { return }
        let finished = kind
        cancel()
        NSSound(named: "Glass")?.play()
        IslandUIState.shared.flash(.timerDone, duration: 4)

        switch finished {
        case .focus:
            focusCount += 1
            if autoContinue { start(seconds: TimeInterval(restMinutes * 60), kind: .rest) }
        case .rest:
            if autoContinue { startPomodoro() }
        case .countdown:
            break
        }
        lastFinishedKind = finished
    }

    @Published private(set) var lastFinishedKind: Kind = .countdown
}

extension TimeInterval {
    /// 1:05:09 / 25:00 / 0:09
    var islandClock: String {
        let total = Int(self.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
