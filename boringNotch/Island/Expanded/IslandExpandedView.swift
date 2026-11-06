//
//  IslandExpandedView.swift
//  MacIsle
//
//  The expanded island: one Apple-style card at a time. Cards are switched with a
//  two-finger horizontal swipe or the page dots; the island morphs to each card's size.
//

import AppKit
import Defaults
import SwiftUI

@MainActor
struct IslandExpandedView: View {
    var size: CGSize
    var namespace: Namespace.ID

    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var agents = AgentCenter.shared

    @State private var scrollMonitor: Any?
    @StateObject private var swipe = IslandSwipeTracker()
    @State private var direction: CGFloat = 1
    /// Larger after a swipe so the incoming card continues the finger's motion.
    @State private var slideDistance: CGFloat = 26

    private var tabs: [IslandTab] { IslandTab.available(musicActive: !music.isPlayerIdle || music.isPlaying) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                page(ui.tab)
                    .id(ui.tab)
                    .transition(pageTransition)
            }
            .frame(width: size.width, height: size.height)
            .offset(x: swipe.offset)

            pageDots
                .padding(.bottom, 6)
                .opacity(ui.hint == nil ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            if let hint = ui.hint {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 8.5, weight: .bold))
                    Text("猜你想用 · \(hint)").font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .frame(height: 16)
                .background(Capsule().fill(Color.black.opacity(0.85)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: ui.hint)
        .frame(width: size.width, height: size.height)
        .onAppear(perform: installSwipe)
        .onReceive(NotificationCenter.default.publisher(for: .islandStep)) { note in
            if let delta = note.object as? Int { step(delta) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandJump)) { note in
            if let index = note.object as? Int, tabs.indices.contains(index) { select(tabs[index], bySwipe: true) }
        }
        .onDisappear(perform: removeSwipe)
        .onChange(of: tabs) { _, list in
            if !list.contains(ui.tab) { select(list.first ?? .home) }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandSlideModifier(x: slideDistance * direction, blur: 3, opacity: 0),
                identity: IslandSlideModifier(x: 0, blur: 0, opacity: 1)
            ).animation(IslandMotion.page.delay(0.03)),
            removal: .modifier(
                active: IslandSlideModifier(x: -slideDistance * direction, blur: 3, opacity: 0),
                identity: IslandSlideModifier(x: 0, blur: 0, opacity: 1)
            ).animation(.easeOut(duration: 0.14))
        )
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ tab: IslandTab) -> some View {
        switch tab {
        case .media: IslandMediaPage(namespace: namespace)
        case .agents: IslandAgentsPage()
        case .dossier: IslandDossierPage()
        case .screens: IslandScreensPage()
        case .home: IslandHomePage(namespace: namespace)
        case .calendar:
            CalendarView()
                .environmentObject(vm)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
        case .timer: IslandTimerPage()
        case .system: IslandSystemPage()
        case .clipboard: IslandClipboardPage()
        case .shelf:
            ShelfView()
                .environmentObject(vm)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
    }

    // MARK: Page dots

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(tabs) { tab in
                let selected = tab == ui.tab
                Capsule()
                    .fill(Color.white.opacity(selected ? 0.85 : 0.22))
                    .frame(width: selected ? 12 : 4, height: 4)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { select(tab) }
                    .help(tab.title)
            }
        }
        .animation(IslandMotion.page, value: ui.tab)
    }

    private func select(_ tab: IslandTab, bySwipe: Bool = false) {
        guard tab != ui.tab else { return }
        slideDistance = bySwipe ? 64 : 26
        IslandPredictor.shared.noteManualSwitch()
        ui.showHint(nil)
        let list = tabs
        let from = list.firstIndex(of: ui.tab) ?? 0
        let to = list.firstIndex(of: tab) ?? 0
        direction = to >= from ? 1 : -1
        withAnimation(IslandMotion.page) { ui.tab = tab }
        #if DEBUG
        IslandDebug.log("selected \(tab.rawValue)")
        #endif
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func step(_ delta: Int) {
        let list = tabs
        guard let i = list.firstIndex(of: ui.tab) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        select(list[j], bySwipe: true)
    }

    private func updateSwipeBounds() {
        let list = tabs
        let i = list.firstIndex(of: ui.tab) ?? 0
        swipe.canPrevious = i > 0
        swipe.canNext = i < list.count - 1
    }

    // MARK: Two-finger swipe

    private func installSwipe() {
        guard scrollMonitor == nil else { return }
        let tracker = swipe
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            #if DEBUG
            IslandDebug.log("scroll phase=\(event.phase.rawValue) mom=\(event.momentumPhase.rawValue) dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) precise=\(event.hasPreciseScrollingDeltas) inv=\(event.isDirectionInvertedFromDevice) win=\(String(describing: event.window.map { type(of: $0) })) open=\(vm.notchState == .open)")
            #endif
            guard vm.notchState == .open, Self.isOverIsland(event) else { return event }
            updateSwipeBounds()
            let outcome = tracker.consume(event)
            #if DEBUG
            if outcome == .next || outcome == .previous || event.phase.contains(.ended) {
                IslandDebug.log("outcome=\(outcome) tab=\(ui.tab.rawValue) offset=\(tracker.offset)")
            }
            #endif
            switch outcome {
            case .pass: return event
            case .swallow: return nil
            case .next: step(1); return nil
            case .previous: step(-1); return nil
            }
        }
    }

    /// Some scroll events arrive without a window (e.g. right after the card resized);
    /// fall back to the pointer position so those gestures still page.
    private static func isOverIsland(_ event: NSEvent) -> Bool {
        if event.window is BoringNotchSkyLightWindow { return true }
        guard event.window == nil else { return false }
        #if DEBUG
        if IslandDebug.synthActive { return true }
        #endif
        let p = NSEvent.mouseLocation
        return NSApp.windows.contains { $0 is BoringNotchSkyLightWindow && $0.isVisible && $0.frame.contains(p) }
    }

    private func removeSwipe() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}

extension Notification.Name {
    static let islandStep = Notification.Name("island.step")
    static let islandJump = Notification.Name("island.jump")
}

struct IslandSlideModifier: ViewModifier {
    var x: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Interactive paging for two-finger trackpad swipes (and Shift + mouse wheel).
///  • the card follows the fingers (with rubber-banding at the ends)
///  • on release it pages if moved far enough or flicked fast, otherwise springs back
///  • direction is decided from the first few points of travel, biased towards horizontal
///  • gesture lifecycle is handled first, so a finished gesture always unlocks the next
@MainActor
final class IslandSwipeTracker: ObservableObject {
    enum Outcome { case pass, swallow, next, previous }
    private enum Axis { case undecided, horizontal, vertical }

    /// Visual drag offset of the current card.
    @Published private(set) var offset: CGFloat = 0
    var canNext = true
    var canPrevious = true

    private var axis: Axis = .undecided
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var raw: CGFloat = 0
    private var committed = false
    private var samples: [(t: TimeInterval, dx: CGFloat)] = []
    private var lastDiscreteStep = Date.distantPast

    private var commitDistance: CGFloat { CGFloat(IslandSettings.shared.swipeCommit) }
    private var flickDistance: CGFloat { CGFloat(IslandSettings.shared.swipeFlick) }
    private var instantDistance: CGFloat { max(90, commitDistance * 2.6) }
    private let flickVelocity: CGFloat = 320

    func consume(_ event: NSEvent) -> Outcome {
        // Classic mouse wheels: no phases, coarse deltas (Shift + wheel scrolls horizontally).
        if !event.hasPreciseScrollingDeltas {
            let dx = event.scrollingDeltaX
            guard abs(dx) > abs(event.scrollingDeltaY), abs(dx) > 0.5 else { return .pass }
            guard Date.now.timeIntervalSince(lastDiscreteStep) > 0.3 else { return .swallow }
            lastDiscreteStep = .now
            return dx < 0 ? .next : .previous
        }

        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            begin()
            if event.phase.contains(.mayBegin) { return .pass }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            return finish()
        }

        // Momentum after the fingers lift belongs to the gesture that produced it.
        if !event.momentumPhase.isEmpty {
            return axis == .horizontal ? .swallow : .pass
        }

        // Follow the fingers regardless of the "natural scrolling" preference.
        var dx = event.scrollingDeltaX
        if !event.isDirectionInvertedFromDevice { dx = -dx }
        let dy = event.scrollingDeltaY

        if axis == .undecided {
            travelX += abs(dx)
            travelY += abs(dy)
            raw += dx
            guard travelX + travelY > 4 else { return .swallow }
            axis = travelX >= travelY * 0.8 ? .horizontal : .vertical
            if axis == .vertical { raw = 0; return .pass }
        } else {
            guard axis == .horizontal else { return .pass }
            guard !committed else { return .swallow }
            raw += dx
        }

        samples.append((ProcessInfo.processInfo.systemUptime, dx))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
        offset = rubberBand(raw)

        // Long, deliberate swipes page immediately without waiting for lift-off.
        if abs(raw) > instantDistance, let outcome = commit(raw < 0) { return outcome }
        return .swallow
    }

    private func begin() {
        axis = .undecided
        travelX = 0
        travelY = 0
        raw = 0
        committed = false
        samples.removeAll()
    }

    private func finish() -> Outcome {
        defer { begin() }
        guard axis == .horizontal else { return .pass }
        guard !committed else { return .swallow }
        let v = velocity()
        let forward = raw < -commitDistance || (v < -flickVelocity && raw < -flickDistance)
        let backward = raw > commitDistance || (v > flickVelocity && raw > flickDistance)
        if forward, let o = commit(true) { return o }
        if backward, let o = commit(false) { return o }
        springBack()
        return .swallow
    }

    private func commit(_ forward: Bool) -> Outcome? {
        guard forward ? canNext : canPrevious else {
            springBack()
            committed = true
            return .swallow
        }
        committed = true
        withAnimation(IslandMotion.page) { offset = 0 }
        return forward ? .next : .previous
    }

    private func springBack() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { offset = 0 }
    }

    /// Points per second over the last ~80 ms.
    private func velocity() -> CGFloat {
        let now = ProcessInfo.processInfo.systemUptime
        let recent = samples.filter { now - $0.t < 0.08 }
        guard let first = recent.first, recent.count > 1 else { return 0 }
        let dt = max(now - first.t, 0.016)
        return recent.reduce(0) { $0 + $1.dx } / CGFloat(dt)
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let allowed = x < 0 ? canNext : canPrevious
        if allowed { return x * 0.6 }
        // Past the first / last card: resist strongly, iOS-style.
        let d = abs(x)
        return (x < 0 ? -1 : 1) * (1 - 1 / (d * 0.012 + 1)) * 40
    }
}
