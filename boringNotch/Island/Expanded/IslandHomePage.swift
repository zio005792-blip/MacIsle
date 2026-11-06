//
//  IslandHomePage.swift
//  boringNotch – Dynamic Island skin
//
//  Glanceable overview: clock, now playing / next event, quick actions.
//

import EventKit
import SwiftUI

@MainActor
struct IslandHomePage: View {
    var namespace: Namespace.ID

    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var ui = IslandUIState.shared
    @ObservedObject private var upcoming = UpcomingEvents.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            clock
                .frame(width: 92, alignment: .leading)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 4)
            eventDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            IslandQuickActions()
                .frame(width: 88)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 20)
        .onAppear { upcoming.refresh() }
    }

    // MARK: Clock

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 1) {
                Text(ctx.date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN")).weekday(.wide)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.38, blue: 0.34))
                Text(ctx.date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN")).month(.wide).day()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Text(ctx.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: ctx.date.formatted(.dateTime.minute()))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    @ViewBuilder
    private var eventDetail: some View {
        switch upcoming.status {
        case .needsAccess:
            VStack(alignment: .leading, spacing: 6) {
                Label("日程", systemImage: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Text("连接日历后，这里会显示下一个会议的倒计时。")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Button("允许访问日历") { upcoming.requestAccess() }
                    .buttonStyle(IslandPillButtonStyle())
            }
        case .ready:
            if let next = upcoming.next {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(cgColor: next.color)).frame(width: 7, height: 7)
                            Text(next.isOngoing(at: ctx.date) ? "进行中" : "下一项")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(next.relative(at: ctx.date))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(next.isSoon(at: ctx.date) ? Color.orange : .white.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                        Text(next.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(next.timeRange)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        if let url = next.meetingURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("加入会议", systemImage: "video.fill")
                            }
                            .buttonStyle(IslandPillButtonStyle(tint: .green))
                            .padding(.top, 2)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("日程", systemImage: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(.green)
                    Text("接下来 24 小时没有日程").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Quick actions

@MainActor
struct IslandQuickActions: View {
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var timer = IslandTimer.shared
    @ObservedObject private var ui = IslandUIState.shared

    var body: some View {
        let columns = [GridItem(.fixed(40), spacing: 8), GridItem(.fixed(40), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 6) {
            IslandToggleTile(symbol: "cup.and.saucer.fill", title: "防休眠", isOn: awake.isActive,
                             tint: Color(red: 0.85, green: 0.62, blue: 0.38)) {
                awake.toggle()
            }
            IslandToggleTile(symbol: "brain.head.profile", title: timer.isActive ? "专注中" : "番茄钟", isOn: timer.isActive,
                             tint: IslandTimer.Kind.focus.tint) {
                if timer.isActive {
                    withAnimation(IslandMotion.page) { ui.tab = .timer }
                } else {
                    timer.startPomodoro()
                }
            }
            IslandToggleTile(symbol: "camera.viewfinder", title: "截图", isOn: false, tint: .white) {
                IslandActions.screenshot()
            }
            IslandToggleTile(symbol: "moon.fill", title: "深色", isOn: IslandActions.isDarkMode, tint: .indigo) {
                IslandActions.toggleDarkMode()
            }
        }
    }
}

struct IslandToggleTile: View {
    var symbol: String
    var title: String
    var isOn: Bool
    var tint: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : Color.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isOn ? tint : Color.white.opacity(hovering ? 0.2 : 0.12)))
                    .symbolEffect(.bounce, value: isOn)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        .help(title)
    }
}

struct IslandPillButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint == .white ? Color.white : Color.black)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(tint == .white ? Color.white.opacity(0.14) : tint))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - System actions

@MainActor
enum IslandActions {
    /// Interactive screenshot straight to the clipboard (shows up in clipboard history).
    static func screenshot() {
        BoringViewCoordinator.shared.toggleExpandingView(status: false, type: .battery)
        NotificationCenter.default.post(name: .islandRequestClose, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-c"]
            try? p.run()
        }
    }

    static var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}

extension Notification.Name {
    static let islandRequestClose = Notification.Name("island.requestClose")
}

// MARK: - Upcoming events (EventKit, read-only)

struct IslandEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: CGColor
    let meetingURL: URL?

    func isOngoing(at date: Date) -> Bool { start <= date && date < end }
    func isSoon(at date: Date) -> Bool { !isOngoing(at: date) && start.timeIntervalSince(date) < 15 * 60 }

    func relative(at date: Date) -> String {
        if isOngoing(at: date) {
            let left = Int(end.timeIntervalSince(date) / 60)
            return "还剩 \(max(1, left)) 分钟"
        }
        let mins = Int(ceil(start.timeIntervalSince(date) / 60))
        if mins < 60 { return "\(max(1, mins)) 分钟后" }
        let hours = mins / 60, rest = mins % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
    }

    var timeRange: String {
        let f = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        let day = Calendar.current.isDateInToday(start) ? "" : "明天 "
        return day + start.formatted(f) + " – " + end.formatted(f)
    }
}

@MainActor
final class UpcomingEvents: ObservableObject {
    static let shared = UpcomingEvents()

    enum Status { case needsAccess, ready }

    @Published private(set) var status: Status = .needsAccess
    @Published private(set) var next: IslandEvent?

    private let store = EKEventStore()
    private var lastRefresh: Date = .distantPast

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .denied || status == .restricted || status == .writeOnly {
            // Already answered once – macOS won't ask again, so open the right Settings pane.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        // The permission sheet needs a frontmost app; the island is a background accessory.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            _ = try? await store.requestFullAccessToEvents()
            NSApp.setActivationPolicy(.accessory)
            refresh(force: true)
            await CalendarManager.shared.checkCalendarAuthorization()
        }
    }

    func refresh(force: Bool = false) {
        let auth = EKEventStore.authorizationStatus(for: .event)
        guard auth == .fullAccess else {
            status = .needsAccess
            next = nil
            return
        }
        status = .ready
        guard force || Date.now.timeIntervalSince(lastRefresh) > 30 else { return }
        lastRefresh = .now

        let now = Date.now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .first
        next = event.map {
            IslandEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                        title: $0.title ?? "日程",
                        start: $0.startDate, end: $0.endDate,
                        color: $0.calendar?.cgColor ?? CGColor(red: 1, green: 0.4, blue: 0.3, alpha: 1),
                        meetingURL: Self.meetingURL(in: $0))
        }
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let haystack = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: haystack, range: NSRange(haystack.startIndex..., in: haystack))
        return matches.compactMap(\.url).first(where: isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        let host = url.host ?? ""
        return ["zoom.us", "meet.google.com", "teams.microsoft.com", "meeting.tencent.com", "webex.com", "feishu.cn", "larksuite.com", "dingtalk.com"]
            .contains { host.hasSuffix($0) }
    }
}
