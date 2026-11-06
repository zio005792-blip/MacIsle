//
//  IslandWorkflowPages.swift
//  MacIsle
//
//  Cards built around a solo iOS / game developer's day: AI agent tasks and
//  App Store screenshot export.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - AI tasks

@MainActor
struct IslandAgentsPage: View {
    @ObservedObject private var agents = AgentCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI 任务")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if agents.sessions.contains(where: { !$0.isActive }) {
                    Button("清除已完成") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { agents.clearFinished() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(agents.sessions) { session in
                        row(session)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agents.sessions)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 18)
    }

    private func row(_ s: AgentSession) -> some View {
        Button {
            agents.reveal(s)
            NotificationCenter.default.post(name: .islandRequestClose, object: nil)
        } label: {
            HStack(spacing: 9) {
                AgentGlyph(session: s, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(s.detail.isEmpty ? s.tool.name : "\(s.tool.name) · \(s.detail)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(s.stateText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(stateColor(s))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(s.elapsed(at: ctx.date).islandClock)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(IslandPressStyle())
        .contextMenu {
            Button("移除") { agents.dismiss(s) }
        }
    }

    private func stateColor(_ s: AgentSession) -> Color {
        switch s.state {
        case .working: return s.tool.tint
        case .attention: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}

// MARK: - App Store screenshots

@MainActor
struct IslandScreensPage: View {
    @ObservedObject private var store = StoreScreenshots.shared
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 12) {
            dropZone
                .frame(width: 128)
            VStack(alignment: .leading, spacing: 7) {
                Text("导出尺寸")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(StoreDevice.all) { device in
                        chip(device)
                    }
                }
                Spacer(minLength: 0)
                Text(store.lastResult ?? "导出到「下载」· 无透明 PNG")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(store.lastResult == nil ? 0.35 : 0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 22)
    }

    private var dropZone: some View {
        Button { store.pickFiles() } label: {
            VStack(spacing: 6) {
                if store.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "iphone.gen3.badge.play")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.7))
                        .symbolEffect(.bounce, value: targeted)
                }
                Text(targeted ? "松手开始转换" : "拖入截图")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("或点击选择")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.22))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(targeted ? 0.1 : 0.04)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(IslandPressStyle())
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            store.handleDrop(providers)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: targeted)
    }

    private func chip(_ device: StoreDevice) -> some View {
        let on = store.selected.contains(device.id)
        return Button { store.toggle(device) } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(on ? Color.accentColor : .white.opacity(0.35))
                Text(device.short)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white.opacity(on ? 0.95 : 0.55))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(on ? 0.12 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .help("\(device.name) · \(Int(device.portrait.width))×\(Int(device.portrait.height))")
    }
}
