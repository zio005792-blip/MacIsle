//
//  IslandRootView.swift
//  MacIsle
//
//  Root view of the island window. Decides what to present, morphs the liquid body
//  between presentations and routes hover / click / drag interactions.
//

import Combine
import Defaults
import SwiftUI

@MainActor
struct IslandRootView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var timer = IslandTimer.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var agents = AgentCenter.shared
    @ObservedObject private var dossier = DossierCenter.shared

    @Namespace private var namespace
    @State private var hovering = false
    @State private var pressed = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dropDebounce: Task<Void, Never>?
    @State private var pendingTab: IslandTab?
    @State private var hapticTick = false
    /// Dwell bookkeeping for hover-to-open. A reference type, so polling never re-renders the view.
    @State private var dwell = HoverDwell()
    private static let hoverPoll = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var metrics: IslandMetrics { IslandMetrics(screenUUID: vm.screenUUID) }

    // MARK: - What to show

    /// Live activities in priority order. The first one owns the island, the second gets the bubble.
    private var activities: [IslandActivity] {
        var list: [IslandActivity] = []
        if agents.needsAttention != nil { list.append(.agent) }
        if dossier.isBusy { list.append(.dossier) }
        if agents.needsAttention == nil, agents.primary != nil { list.append(.agent) }
        if timer.isActive { list.append(.timer) }
        if coordinator.musicLiveActivityEnabled && (music.isPlaying || !music.isPlayerIdle) { list.append(.music) }
        if awake.isActive { list.append(.keepAwake) }
        return list
    }

    private var presentation: IslandPresentation {
        if vm.notchState == .open { return .expanded(ui.tab) }
        if coordinator.sneakPeek.show, let hud = hudKind(coordinator.sneakPeek.type) { return .hud(hud) }
        if let alert = ui.alert { return .alert(alert) }
        if coordinator.expandingView.show, coordinator.expandingView.type == .battery,
           Defaults[.showPowerStatusNotifications] {
            return .alert(.power(plugged: battery.isPluggedIn))
        }
        if vm.hideOnClosed { return .hidden }
        if let first = activities.first { return .compact(first) }
        return ui.showIdlePill ? .idle : .hidden
    }

    private var bubbleActivity: IslandActivity? {
        guard case .compact = presentation else { return nil }
        return activities.dropFirst().first
    }

    private func hudKind(_ type: SneakContentType) -> IslandHUDKind? {
        switch type {
        case .volume: return .volume
        case .brightness: return .brightness
        case .backlight: return .backlight
        case .mic: return .mic
        default: return nil
        }
    }

    private func animation(for p: IslandPresentation) -> Animation {
        switch p {
        case .expanded: return IslandMotion.open
        case .hidden: return IslandMotion.close
        default: return vm.notchState == .closed ? IslandMotion.morph : IslandMotion.close
        }
    }

    // MARK: - Body

    var body: some View {
        let p = presentation
        let m = metrics
        let size = m.size(for: p)
        let radius = m.cornerRadius(for: p, size: size)
        let bubble = bubbleActivity
        let d = m.bubbleDiameter
        let scale: CGFloat = p.isExpanded ? 1 : (pressed ? 0.97 : (hovering ? 1.03 : 1))

        let geometry = IslandBodyGeometry(
            width: size.width,
            height: size.height,
            radius: radius,
            topGap: m.topGap,
            bubbleRadius: bubble == nil ? 0 : d / 2,
            bubbleGap: bubble == nil ? -d : m.bubbleGap,
            scale: scale,
            flushTop: m.flushTop
        )

        ZStack(alignment: .top) {
            IslandBodyView(
                geometry: geometry,
                shadowOpacity: p.isExpanded ? 0.55 : (hovering ? 0.28 : 0.0),
                keylineOpacity: p.isExpanded ? 0.10 : 0.07,
                restingBubbleRadius: d / 2,
                camera: ui.showCamera && p != .hidden && !m.flushTop
                    ? (offsetX: m.cameraOffset, centerY: m.topGap + m.compactHeight / 2, diameter: m.cameraDiameter)
                    : nil
            )
            .opacity(p == .hidden ? 0 : 1)

            // Content lives in a window-sized layer clipped by the *same* animatable
            // geometry as the body, so it can never spill outside the shape mid-spring.
            ZStack(alignment: .top) {
                islandContent(p, size: size)
                    .scaleEffect(scale, anchor: .top)
                    .padding(.top, m.topGap)
            }
            .frame(width: IslandMetrics.windowSize.width, height: IslandMetrics.windowSize.height, alignment: .top)
            .clipShape(IslandMainShape(geometry: geometry))
            .contentShape(IslandMainShape(geometry: geometry))
            .allowsHitTesting(p != .hidden)
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                guard vm.notchState == .closed else { return false }
                vm.dropEvent = true
                ShelfStateViewModel.shared.load(providers)
                return true
            }
            .onHover(perform: handleHover)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if vm.notchState == .closed && !pressed { withAnimation(IslandMotion.touch) { pressed = true } }
                    }
                    .onEnded { _ in withAnimation(IslandMotion.touch) { pressed = false } }
            )
            .onTapGesture {
                if vm.notchState == .closed { open(to: nil) }
            }
            .contextMenu {
                Button(tr("设置…", "Settings…")) { SettingsWindowController.shared.showWindow() }
                Divider()
                Button(awake.isActive ? tr("关闭防休眠", "Stop Keep Awake") : tr("防休眠", "Awake")) { awake.toggle() }
                Button(timer.isActive ? tr("结束计时", "End Timer") : tr("开始番茄钟", "Start Pomodoro")) {
                    timer.isActive ? timer.cancel() : timer.startPomodoro()
                }
                Toggle(tr("显示摄像头", "Show Camera"), isOn: $ui.showCamera)
            }

            if let bubble {
                IslandBubbleContent(activity: bubble, diameter: d)
                    .contentShape(Circle())
                    .onTapGesture { open(to: tab(for: bubble)) }
                    .offset(x: size.width * scale / 2 + m.bubbleGap * scale + d * scale / 2,
                            y: m.topGap + (size.height * scale - d) / 2)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.12)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            }
        }
        .frame(width: IslandMetrics.windowSize.width, height: IslandMetrics.windowSize.height, alignment: .top)
        // One implicit animation for every presentation change (shape, bubble, size) so the
        // body, clip and content always share a single spring. Hover/press use explicit touch springs.
        .animation(animation(for: p), value: "\(p.key)|\(bubble?.rawValue ?? "-")|\(Int(size.width))x\(Int(size.height))")
        .preferredColorScheme(.dark)
        .sensoryFeedback(.alignment, trigger: hapticTick)
        .onChange(of: vm.notchState) { _, state in
            guard state == .open else {
                dwell.armed = false
                IslandPredictor.shared.learn(finalTab: ui.tab)
                ui.showHint(nil)
                return
            }
            let available = IslandTab.available(musicActive: !music.isPlayerIdle || music.isPlaying)
            let dragging = vm.anyDropZoneTargeting || vm.dragDetectorTargeting || coordinator.currentView == .shelf && NSEvent.pressedMouseButtons != 0
            if let pendingTab, available.contains(pendingTab) {
                // Opened from a specific activity / bubble: go exactly there.
                ui.tab = pendingTab
                _ = IslandPredictor.shared.guess(available: available, dragging: dragging)
            } else if ui.alert == .agent {
                ui.tab = .agents
                _ = IslandPredictor.shared.guess(available: available, dragging: dragging)
            } else if ui.alert == .dossier {
                ui.tab = .dossier
                _ = IslandPredictor.shared.guess(available: available, dragging: dragging)
            } else if IslandSettings.shared.predict {
                let guess = IslandPredictor.shared.guess(available: available, dragging: dragging)
                ui.tab = guess.tab
                // Explain the guess only when it isn't the obvious default.
                ui.showHint(IslandSettings.shared.predictHint && guess.tab != .home && !guess.reason.isEmpty ? guess.reason : nil)
            } else {
                _ = IslandPredictor.shared.guess(available: available, dragging: dragging)
                if !available.contains(ui.tab) { ui.tab = available.first ?? .home }
            }
            pendingTab = nil
            ui.dismissAlert()
            UpcomingEvents.shared.refresh()
        }
        .onChange(of: coordinator.currentView) { _, view in
            if view == .shelf && vm.notchState == .open && ![.dossier, .screens].contains(ui.tab) {
                let guess = IslandPredictor.shared.guess(
                    available: IslandTab.available(musicActive: !music.isPlayerIdle || music.isPlaying), dragging: true)
                ui.tab = guess.tab
                ui.showHint(guess.tab != .shelf ? guess.reason : nil)
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, targeted in
            handleDropTargeting(targeted)
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandRequestClose)) { _ in
            close()
        }
        .onReceive(Self.hoverPoll) { _ in
            pollHoverZone()
        }
        .onAppear {
            if coordinator.helloAnimationRunning { vm.closeHello() }
            // Background services start with the app, not when their card is first shown.
            _ = ClipboardHistory.shared
            _ = AgentCenter.shared
            _ = DossierCenter.shared
            #if DEBUG
            IslandDebug.install(vm: vm)
            #endif
            UpcomingEvents.shared.refresh()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func islandContent(_ p: IslandPresentation, size: CGSize) -> some View {
        let m = metrics
        // On notch screens tall content starts below the physical notch.
        let inset: CGFloat = m.flushTop && size.height > m.compactHeight + 1 ? m.notchInset : 0
        let contentSize = CGSize(width: size.width, height: size.height - inset)
        ZStack(alignment: .top) {
            Group {
                switch p {
                case .expanded:
                    IslandExpandedView(size: contentSize, namespace: namespace)
                        .environmentObject(vm)
                case .hidden, .idle:
                    Color.clear.frame(width: contentSize.width, height: contentSize.height)
                default:
                    IslandCompactContent(presentation: p, size: contentSize, metrics: m, namespace: namespace)
                }
            }
            .id(p.key)
            .transition(.islandContent)
            .padding(.top, inset)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    // MARK: - Interaction

    private func tab(for activity: IslandActivity) -> IslandTab {
        switch activity {
        case .agent: return .agents
        case .dossier: return .dossier
        case .timer: return .timer
        case .music: return .media
        case .keepAwake, .charging: return .home
        }
    }

    private func defaultTab() -> IslandTab {
        if ui.alert == .agent { return .agents }
        if let first = activities.first { return tab(for: first) }
        return .home
    }

    private func open(to tab: IslandTab?) {
        hoverTask?.cancel()
        pendingTab = tab
        pressed = false
        withAnimation(IslandMotion.open) { vm.open() }
    }

    private func close() {
        hoverTask?.cancel()
        guard vm.notchState == .open else { return }
        withAnimation(IslandMotion.close) { vm.close() }
    }

    /// Hover-to-open zone: the footprint the island will occupy once expanded (screen coordinates).
    private func expandedZone() -> NSRect? {
        guard let window = NSApp.windows.first(where: { $0 is BoringNotchSkyLightWindow && $0.isVisible }) else { return nil }
        let m = metrics
        let size = m.size(for: .expanded(ui.tab))
        let top = window.frame.maxY
        return NSRect(x: window.frame.midX - size.width / 2, y: top - m.topGap - size.height,
                      width: size.width, height: size.height + m.topGap)
    }

    /// Polled while closed: open when the pointer rests inside the expanded footprint.
    private func pollHoverZone() {
        guard vm.notchState == .closed, Defaults[.openNotchOnHover], !coordinator.firstLaunch,
              presentation != .hidden, !coordinator.sneakPeek.show,
              NSEvent.pressedMouseButtons == 0, let zone = expandedZone() else {
            #if DEBUG
            if let z = expandedZone() { IslandDebug.lastZone = z }
            #endif
            dwell.reset()
            return
        }
        var p = NSEvent.mouseLocation
        #if DEBUG
        if let fake = IslandDebug.fakeMouse { p = fake }
        #endif
        guard zone.contains(p) else { dwell.reset(); dwell.armed = true; return }
        // After the island closes, the pointer has to leave the area once before it can re-open.
        guard dwell.armed else { return }
        if let anchor = dwell.point, hypot(p.x - anchor.x, p.y - anchor.y) <= 10 {
            if Date.now.timeIntervalSince(dwell.since) >= max(0.12, Defaults[.minimumHoverDuration]) {
                dwell.reset()
                dwell.armed = false
                open(to: nil)
            }
        } else {
            dwell.point = p          // entered or moved: start waiting again
            dwell.since = .now
        }
    }

    private func handleHover(_ isHovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if isHovering {
            if !hovering && vm.notchState == .closed && Defaults[.enableHaptics] { hapticTick.toggle() }
            withAnimation(IslandMotion.touch) { hovering = true }
            // Opening is handled by pollHoverZone (expanded-footprint dwell).
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(vm.notchState == .open ? 220 : 60))
                guard !Task.isCancelled else { return }
                withAnimation(IslandMotion.touch) {
                    hovering = false
                    pressed = false
                }
                if vm.notchState == .open,
                   !ui.keyboardFocus,
                   !vm.isBatteryPopoverActive,
                   !vm.anyDropZoneTargeting,
                   !SharingStateManager.shared.preventNotchClose {
                    close()
                }
            }
        }
    }

    private func handleDropTargeting(_ targeted: Bool) {
        dropDebounce?.cancel()
        if targeted {
            if vm.notchState == .closed { open(to: nil) }
            return
        }
        dropDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if vm.dropEvent {
                vm.dropEvent = false
                return
            }
            if !hovering && !SharingStateManager.shared.preventNotchClose { close() }
        }
    }
}

/// Mutable hover-dwell state that SwiftUI doesn't observe.
final class HoverDwell {
    var point: NSPoint?
    var since = Date.distantFuture
    var armed = true
    func reset() { point = nil }
}
