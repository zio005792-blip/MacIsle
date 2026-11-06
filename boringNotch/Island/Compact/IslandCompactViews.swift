//
//  IslandCompactViews.swift
//  MacIsle
//
//  Content for the resting, compact, HUD and alert presentations, plus the bubble.
//

import Defaults
import SwiftUI

@MainActor
struct IslandCompactContent: View {
    var presentation: IslandPresentation
    var size: CGSize
    var metrics: IslandMetrics
    var namespace: Namespace.ID

    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var timer = IslandTimer.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var agents = AgentCenter.shared
    @ObservedObject private var dossier = DossierCenter.shared

    private var tint: Color { Color.islandTint(music.avgColor) }

    var body: some View {
        switch presentation {
        case .compact(let activity):
            compact(activity)
        case .hud(let kind):
            hud(kind)
        case .alert(let alert):
            alertView(alert)
        default:
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    // MARK: Compact activities

    @ViewBuilder
    private func compact(_ activity: IslandActivity) -> some View {
        let side = metrics.sideWidth(for: activity)
        let h = metrics.compactHeight
        switch activity {
        case .dossier:
            IslandCompactLayout(size: size, sideWidth: side) {
                ZStack {
                    IslandRing(progress: max(0.03, dossier.progress), tint: .accentColor, lineWidth: 2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: dossier.progress)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: h * 0.3, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: h - 7, height: h - 7)
            } trailing: {
                if case .scanning(let done, let total, _) = dossier.phase {
                    Text("\(done)/\(max(total, 1))")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                }
            }
        case .agent:
            if let session = agents.primary {
                IslandCompactLayout(size: size, sideWidth: side) {
                    AgentGlyph(session: session, size: h - 6)
                } trailing: {
                    Group {
                        if session.state == .attention {
                            Text(tr("确认", "Review"))
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(Color.orange)
                                .islandBreathing()
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(session.elapsed(at: ctx.date).islandClock)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(session.tool.tint)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if agents.active.count > 1 {
                            Text("\(agents.active.count)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(Color.white.opacity(0.85)))
                                .offset(x: 6, y: -1)
                        }
                    }
                }
            }
        case .music:
            IslandCompactLayout(size: size, sideWidth: side) {
                IslandAlbumArt(image: music.albumArt, size: h - 6, radius: (h - 6) * 0.26, dimmed: !music.isPlaying)
                    .matchedGeometryEffect(id: "island.art", in: namespace)
            } trailing: {
                IslandWaveform(color: tint, isPlaying: music.isPlaying, bars: 4, barWidth: 2, spacing: 1.8)
                    .frame(width: 16, height: h * 0.5)
            }
        case .timer:
            IslandCompactLayout(size: size, sideWidth: side) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !timer.isRunning)) { ctx in
                    ZStack {
                        IslandRing(progress: 1 - timer.progress(at: ctx.date), tint: timer.kind.tint, lineWidth: 2)
                        if !timer.isRunning {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(timer.kind.tint)
                        }
                    }
                    .frame(width: h - 7, height: h - 7)
                }
            } trailing: {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    Text(timer.remaining(at: ctx.date).islandClock)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timer.kind.tint)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(timer.remaining(at: ctx.date)))
                }
            }
        case .keepAwake:
            IslandCompactLayout(size: size, sideWidth: side) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.62, blue: 0.38))
                    .islandBreathing()
            } trailing: {
                Image(systemName: "infinity")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color(red: 0.85, green: 0.62, blue: 0.38))
            }
        case .charging:
            IslandCompactLayout(size: size, sideWidth: side) {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
            } trailing: {
                Text("\(Int(battery.levelBattery))%").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.green)
            }
        }
    }

    // MARK: HUD (volume / brightness / backlight / mic)

    @ViewBuilder
    private func hud(_ kind: IslandHUDKind) -> some View {
        let value = Double(coordinator.sneakPeek.value)
        IslandCompactLayout(size: size, sideWidth: metrics.compactHeight + 46) {
            HStack {
                Image(systemName: hudSymbol(kind, value: value), variableValue: kind == .mic ? nil : value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
        } trailing: {
            if kind == .mic {
                Text(value > 0 ? tr("已开启", "On") : tr("已静音", "Muted"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(value > 0 ? .white : .red)
            } else {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Color.white)
                                .frame(width: max(4, geo.size.width * value))
                        }
                    }
                    .frame(width: 40, height: 4)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 22, alignment: .trailing)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(value * 100))
                }
                .padding(.trailing, 4)
            }
        }
    }

    private func hudSymbol(_ kind: IslandHUDKind, value: Double) -> String {
        switch kind {
        case .volume: return value <= 0.001 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .backlight: return "light.max"
        case .mic: return value > 0 ? "mic.fill" : "mic.slash.fill"
        }
    }

    // MARK: Alerts

    @ViewBuilder
    private func alertView(_ alert: IslandAlert) -> some View {
        switch alert {
        case .power(let plugged):
            IslandCompactLayout(size: size, sideWidth: metrics.compactHeight + 58) {
                HStack(spacing: 5) {
                    Image(systemName: plugged ? "bolt.fill" : "powerplug.portrait")
                        .font(.system(size: 11.5, weight: .bold))
                        .symbolEffect(.bounce, value: plugged)
                    Text(plugged ? tr("充电中", "Charging") : tr("使用电池", "On battery"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(plugged ? Color.green : Color.white)
            } trailing: {
                HStack(spacing: 5) {
                    Text("\(Int(battery.levelBattery))%")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    batteryGlyph
                }
                .foregroundStyle(plugged ? Color.green : Color.white)
            }
        case .track:
            HStack(spacing: 10) {
                IslandAlbumArt(image: music.albumArt, size: size.height - 22, radius: 9)
                    .matchedGeometryEffect(id: "island.art", in: namespace)
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.songTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(music.artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint.opacity(0.9))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                IslandWaveform(color: tint, isPlaying: music.isPlaying)
                    .frame(width: 24, height: 14)
            }
            .padding(.horizontal, 12)
            .frame(width: size.width, height: size.height)
        case .timerDone:
            let kind = timer.lastFinishedKind
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(kind.tint.opacity(0.22))
                    Image(systemName: kind == .focus ? "checkmark" : (kind == .rest ? "figure.walk" : "bell.fill"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(kind.tint)
                        .symbolEffect(.bounce, options: .repeat(2))
                }
                .frame(width: size.height - 22, height: size.height - 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind == .focus ? tr("专注完成", "Focus done") : (kind == .rest ? tr("休息结束", "Break over") : tr("计时结束", "Timer done")))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(timerDoneSubtitle(kind))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: size.width, height: size.height)
        case .agent:
            if let session = agents.spotlight {
                HStack(spacing: 10) {
                    AgentGlyph(session: session, size: size.height - 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agentHeadline(session))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(session.detail.isEmpty ? session.title : "\(session.title) · \(session.detail)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 6)
                    if (session.state == .done || session.state == .failed) && session.elapsed() >= 1 {
                        Text(session.elapsed().islandClock)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: size.width, height: size.height)
            }
        case .dossier:
            let pending = dossier.pendingConfirmations.count
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill((pending > 0 ? Color.orange : Color.green).opacity(0.22))
                    Image(systemName: pending > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(pending > 0 ? Color.orange : Color.green)
                        .symbolEffect(.bounce, value: pending)
                }
                .frame(width: size.height - 24, height: size.height - 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("资料识别完成", "Dossier ready"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(pending > 0 ? tr("\(dossier.documents.count) 份 · \(pending) 项信息不一致，点开确认", "\(dossier.documents.count) files · \(pending) mismatches, tap to review") : tr("\(dossier.documents.count) 份 · 关键信息一致，可生成文档", "\(dossier.documents.count) files · key facts match, ready to export"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: size.width, height: size.height)
        case .copied:
            IslandCompactLayout(size: size, sideWidth: metrics.compactHeight + 70) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .symbolEffect(.bounce, value: ui.copiedPreview)
                    Text(tr("已复制", "Copied")).font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.green)
            } trailing: {
                Text(ui.copiedPreview)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, 6)
            }
        }
    }

    private func agentHeadline(_ s: AgentSession) -> String {
        switch s.state {
        case .attention: return tr("\(s.tool.name) 等你确认", "\(s.tool.name) needs you")
        case .done: return s.tool == .shell ? tr("命令已完成", "Command finished") : tr("\(s.tool.name) 已完成", "\(s.tool.name) finished")
        case .failed: return s.tool == .shell ? tr("命令失败", "Command failed") : tr("\(s.tool.name) 出错了", "\(s.tool.name) failed")
        case .working: return tr("\(s.tool.name) 运行中", "\(s.tool.name) running")
        }
    }

    private func timerDoneSubtitle(_ kind: IslandTimer.Kind) -> String {
        switch kind {
        case .focus: return timer.autoContinue ? tr("开始休息 \(timer.restMinutes) 分钟", "Starting a \(timer.restMinutes)-minute break") : tr("今天已完成 \(timer.focusCount) 个番茄", "\(timer.focusCount) pomodoros today")
        case .rest: return timer.autoContinue ? tr("开始新一轮专注", "Starting a new focus round") : tr("准备好了就继续吧", "Continue when you're ready")
        case .countdown: return tr("时间到", "Time's up")
        }
    }

    private var batteryGlyph: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                .fill(battery.isPluggedIn ? Color.green : (battery.levelBattery <= 20 ? Color.red : Color.white))
                .frame(width: max(2, 18 * CGFloat(battery.levelBattery) / 100), height: 7)
                .padding(.leading, 2)
        }
    }
}

// MARK: - Bubble ("minimal" presentation of the second activity)

@MainActor
struct IslandBubbleContent: View {
    var activity: IslandActivity
    var diameter: CGFloat

    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var timer = IslandTimer.shared

    var body: some View {
        Group {
            switch activity {
            case .agent:
                if let session = AgentCenter.shared.primary {
                    AgentGlyph(session: session, size: diameter - 6)
                }
            case .dossier:
                IslandRing(progress: max(0.03, DossierCenter.shared.progress), tint: .accentColor, lineWidth: 2)
                    .frame(width: diameter - 8, height: diameter - 8)
            case .music:
                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter - 6, height: diameter - 6)
                    .clipShape(Circle())
            case .timer:
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !timer.isRunning)) { ctx in
                    IslandRing(progress: 1 - timer.progress(at: ctx.date), tint: timer.kind.tint, lineWidth: 2)
                        .frame(width: diameter - 8, height: diameter - 8)
                }
            case .keepAwake:
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.62, blue: 0.38))
            case .charging:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Agent glyph

/// Tool icon inside a ring that spins while working and pulses orange when it needs you.
struct AgentGlyph: View {
    var session: AgentSession
    var size: CGFloat

    @State private var spin = false

    var body: some View {
        ZStack {
            switch session.state {
            case .working:
                Circle().stroke(session.tool.tint.opacity(0.2), lineWidth: 1.6)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(session.tool.tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            case .attention:
                Circle().fill(Color.orange.opacity(0.25))
                    .islandBreathing()
            case .done:
                Circle().fill(Color.green.opacity(0.22))
            case .failed:
                Circle().fill(Color.red.opacity(0.25))
            }
            Image(systemName: glyph)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
    }

    private var glyph: String {
        switch session.state {
        case .working: return session.tool.symbol
        case .attention: return "hand.raised.fill"
        case .done: return "checkmark"
        case .failed: return "xmark"
        }
    }

    private var color: Color {
        switch session.state {
        case .working: return session.tool.tint
        case .attention: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}
