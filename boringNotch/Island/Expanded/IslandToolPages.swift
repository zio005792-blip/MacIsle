//
//  IslandToolPages.swift
//  MacIsle
//
//  Timer / Pomodoro, system monitor and clipboard history pages.
//

import SwiftUI

// MARK: - Timer

@MainActor
struct IslandTimerPage: View {
    @ObservedObject private var timer = IslandTimer.shared

    private let presets: [Int] = [1, 3, 5, 10, 25, 60]

    var body: some View {
        if timer.isActive {
            running
                .transition(.islandPage)
        } else {
            picker
                .transition(.islandPage)
        }
    }

    private var running: some View {
        HStack(spacing: 18) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !timer.isRunning)) { ctx in
                ZStack {
                    IslandRing(progress: 1 - timer.progress(at: ctx.date), tint: timer.kind.tint, lineWidth: 6)
                    VStack(spacing: 0) {
                        Text(timer.remaining(at: ctx.date).islandClock)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(timer.remaining(at: ctx.date)))
                        Text(timer.kind.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(timer.kind.tint)
                    }
                }
                .frame(width: 96, height: 96)
            }

            VStack(alignment: .leading, spacing: 10) {
                if timer.kind != .countdown {
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i < timer.focusCount % 4 ? IslandTimer.Kind.focus.tint : Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)
                        }
                        Text(tr("今日 \(timer.focusCount) 个", "\(timer.focusCount) today"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.leading, 3)
                    }
                }
                HStack(spacing: 10) {
                    IslandGlyphButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", size: 38,
                                      font: .system(size: 15, weight: .bold), tint: timer.kind.tint) {
                        timer.toggle()
                    }
                    IslandGlyphButton(symbol: "xmark", size: 38, font: .system(size: 13, weight: .bold)) {
                        withAnimation(IslandMotion.page) { timer.cancel() }
                    }
                }
                HStack(spacing: 6) {
                    Button(tr("+1 分", "+1 min")) { timer.add(seconds: 60) }
                    Button(tr("+5 分", "+5 min")) { timer.add(seconds: 300) }
                }
                .buttonStyle(IslandPillButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var picker: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(IslandMotion.page) { timer.startPomodoro() }
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(IslandTimer.Kind.focus.tint.opacity(0.18))
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(IslandTimer.Kind.focus.tint)
                    }
                    .frame(width: 66, height: 66)
                    Text(tr("番茄钟 \(timer.focusMinutes)′", "Pomodoro \(timer.focusMinutes)′"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .buttonStyle(IslandPressStyle())
            .frame(width: 80)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(presets, id: \.self) { m in
                    Button {
                        withAnimation(IslandMotion.page) { timer.start(seconds: TimeInterval(m * 60)) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(m)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(IslandTimer.Kind.countdown.tint)
                            Text(tr("分", "min"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(IslandPressStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 22)
    }
}

// MARK: - System monitor

@MainActor
struct IslandSystemPage: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared

    var body: some View {
        HStack(spacing: 8) {
            tile(title: "CPU", value: "\(Int((monitor.cpu * 100).rounded()))%", tint: .cyan) {
                IslandSparkline(values: monitor.cpuHistory, maxValue: 1, tint: .cyan)
            }
            tile(title: tr("内存", "Memory"), value: monitor.memoryUsed.islandBytes, tint: .purple) {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * monitor.memoryFraction)
                                .animation(.easeOut(duration: 0.3), value: monitor.memoryFraction)
                        }
                    }
                    .frame(height: 8)
                    Text(tr("共 \(monitor.memoryTotal.islandBytes) · \(Int(monitor.memoryFraction * 100))%", "of \(monitor.memoryTotal.islandBytes) · \(Int(monitor.memoryFraction * 100))%"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            tile(title: tr("网络", "Network"), value: "↓ " + monitor.downBytesPerSec.islandRate, tint: .green) {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack {
                        IslandSparkline(values: monitor.downHistory, maxValue: nil, tint: .green)
                        IslandSparkline(values: monitor.upHistory, maxValue: monitor.downHistory.max().map { max($0, 1) }, tint: .orange, filled: false)
                    }
                    Text("↑ " + monitor.upBytesPerSec.islandRate)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    private func tile<Content: View>(title: String, value: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        IslandCard(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                content()
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

struct IslandSparkline: View {
    var values: [Double]
    var maxValue: Double?
    var tint: Color
    var filled: Bool = true

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * step, y: size.height - size.height * CGFloat(min(values[i] / top, 1)) * 0.92)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count {
                let p0 = point(i - 1), p1 = point(i)
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                line.addQuadCurve(to: mid, control: p0)
                if i == values.count - 1 { line.addQuadCurve(to: p1, control: mid) }
            }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .drawingGroup()
    }
}

// MARK: - Clipboard

@MainActor
struct IslandClipboardPage: View {
    @ObservedObject private var history = ClipboardHistory.shared
    @State private var hovered: UUID?

    var body: some View {
        Group {
            if !history.isEnabled {
                placeholder(title: tr("剪贴板历史已关闭", "Clipboard history is off")) {
                    Button(tr("开启", "Turn On")) { history.isEnabled = true }.buttonStyle(IslandPillButtonStyle())
                }
            } else if history.items.isEmpty {
                placeholder(title: tr("复制的内容会出现在这里", "Things you copy will appear here")) {
                    Text(tr("只存在内存里 · 密码管理器的内容会自动跳过", "Kept in memory only · password-manager items are skipped"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(tr("剪贴板 · 点击复制", "Clipboard · click to copy"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Button(tr("清空", "Clear")) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { history.clear() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(history.items) { item in
                                row(item)
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: history.items)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 18)
    }

    private func row(_ item: ClipboardItem) -> some View {
        let transforms: [ClipboardTransform] = {
            if case .text(let s) = item.content { return ClipboardTransforms.suggestions(for: s) }
            return []
        }()
        let isHovered = hovered == item.id
        return HStack(spacing: 8) {
            Group {
                if case .image(let img) = item.content {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else if let bundle = item.sourceBundleID {
                    AppIcon(for: bundle).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 22)
            Text(item.preview)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            ForEach(transforms.prefix(isHovered ? 3 : 1)) { t in
                Button(t.title) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(t.result, forType: .string)
                    IslandUIState.shared.flash(.copied(t.title), duration: 1.6)
                }
                .buttonStyle(IslandChipStyle())
                .help(t.result.count > 300 ? String(t.result.prefix(300)) + "…" : t.result)
            }
            if transforms.isEmpty || !isHovered {
                Text(item.date.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(isHovered ? 0.1 : 0.05)))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { history.copy(item) }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h ? item.id : (hovered == item.id ? nil : hovered) } }
        .contextMenu { Button(tr("删除", "Delete")) { history.remove(item) } }
    }

    private func placeholder<Extra: View>(title: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            extra()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IslandChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.3 : 0.16)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
