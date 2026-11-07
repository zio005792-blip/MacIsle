//
//  IslandAskPage.swift
//  MacIsle
//
//  "Ask AI": a tiny chat with the on-device model, right in the island.
//

import AppKit
import SwiftUI

@MainActor
struct IslandAskPage: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var session = AskSession.shared
    @ObservedObject private var ai = LocalAI.shared
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let turn = session.current {
                answer(turn)
            } else {
                suggestions
            }
            inputBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .task { await ai.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(tr("问 AI", "Ask AI"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(ai.modelName.isEmpty ? ai.status.label : "\(ai.modelName) · \(ai.status.label)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            Spacer()
            if !session.turns.isEmpty {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { session.clear() } } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .help(tr("新对话", "New conversation"))
            }
        }
    }

    private var statusColor: Color {
        switch ai.status {
        case .ready: return .green
        case .sleeping, .loading: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    // MARK: Answer

    private func answer(_ turn: AskSession.Turn) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(turn.label ?? turn.question)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if turn.answer.isEmpty && session.isRunning {
                            ThinkingDots()
                                .padding(.top, 4)
                            if ai.status != .ready {
                                Text(tr("第一次提问需要先加载模型，大约 15 秒…", "Loading the model for the first question, about 15 s…"))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.top, 4)
                            }
                        } else {
                            Text(turn.answer)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(turn.failed ? .orange : .white.opacity(0.92))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: turn.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
            if !turn.answer.isEmpty && !session.isRunning && !turn.failed {
                HStack(spacing: 6) {
                    Button(tr("复制", "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(turn.answer, forType: .string)
                        IslandUIState.shared.flash(.copied(tr("AI 回答", "AI answer")), duration: 1.4)
                    }
                    .buttonStyle(IslandChipStyle())
                    if session.turns.count > 1 {
                        Text(tr("\(session.turns.count) 轮对话", "\(session.turns.count) turns"))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("问点什么，或者对刚复制的内容：", "Ask anything, or use what you just copied:"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            if let text = latestClipboardText {
                HStack(spacing: 6) {
                    ForEach(AskSession.Action.allCases) { action in
                        Button { session.run(action, on: text) } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                        .buttonStyle(IslandChipStyle())
                    }
                }
                Text("“\(text.prefix(60).replacingOccurrences(of: "\n", with: " "))”")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            } else {
                Text(tr("复制一段文字后，这里会出现翻译、总结、润色、解释。", "Copy some text to get Translate, Summarize, Polish and Explain here."))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var latestClipboardText: String? {
        for item in clipboard.items {
            if case .text(let s) = item.content, s.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 { return s }
        }
        return nil
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField(tr("问点什么… 回车发送", "Ask something… Return to send"), text: $session.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .simultaneousGesture(TapGesture().onEnded { beginTyping() })
            if session.isRunning {
                IslandGlyphButton(symbol: "stop.fill", size: 28, font: .system(size: 10, weight: .bold)) { session.stop() }
            } else {
                IslandGlyphButton(symbol: "arrow.up", size: 28, font: .system(size: 12, weight: .bold),
                                  tint: session.draft.isEmpty ? .white.opacity(0.4) : .white) { send() }
            }
        }
        .onAppear { if IslandUIState.shared.keyboardFocus { fieldFocused = true } }
    }

    private func beginTyping() {
        IslandKeyboard.beginTyping(vm)
        fieldFocused = true
    }

    private func send() {
        let q = session.draft
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.draft = ""
        session.ask(q)
    }
}

/// Three softly pulsing dots while the model thinks.
struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.35 + 0.5 * max(0, sin(t * 5 - Double(i) * 0.8))))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
