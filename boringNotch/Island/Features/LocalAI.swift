//
//  LocalAI.swift
//  MacIsle
//
//  Talks to a local, OpenAI-compatible model server — by default the MacIsle gateway in
//  front of the on-device Qwen (MLX) model (scripts/connect-local-ai.sh). Nothing leaves the Mac.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class LocalAI: ObservableObject {
    static let shared = LocalAI()

    enum Status: Equatable {
        case unknown
        case offline          // nothing listening
        case sleeping         // gateway up, model unloaded (loads on first request, ~15 s)
        case loading
        case ready

        var label: String {
            switch self {
            case .unknown: return tr("检查中…", "Checking…")
            case .offline: return tr("未连接", "Not connected")
            case .sleeping: return tr("待命（首次提问会先加载模型）", "Standing by (first question loads the model)")
            case .loading: return tr("模型加载中…", "Loading model…")
            case .ready: return tr("就绪", "Ready")
            }
        }

        var isUsable: Bool { self == .sleeping || self == .loading || self == .ready }
    }

    struct Message: Codable, Equatable {
        let role: String
        let content: String
    }

    @AppStorage("island.ai.endpoint") var endpoint: String = "http://127.0.0.1:8737"
    @Published private(set) var status: Status = .unknown
    @Published private(set) var modelName: String = ""

    private var base: URL? { URL(string: endpoint.trimmingCharacters(in: .whitespaces)) }

    // MARK: Status

    func refresh() async {
        guard let base else { status = .offline; return }
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.timeoutInterval = 1.5
        if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            modelName = obj["model"] as? String ?? ""
            switch obj["backend"] as? String {
            case "ready", "warming": status = .ready
            case "loading": status = .loading
            default: status = .sleeping
            }
            return
        }
        // Any other OpenAI-compatible server (LM Studio, Ollama, mlx_lm.server…).
        var models = URLRequest(url: base.appendingPathComponent("v1/models"))
        models.timeoutInterval = 1.5
        if let (data, resp) = try? await URLSession.shared.data(for: models), (resp as? HTTPURLResponse)?.statusCode == 200 {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let first = (obj?["data"] as? [[String: Any]])?.first?["id"] as? String
            modelName = first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            status = .ready
            return
        }
        status = .offline
    }

    // MARK: Generation

    /// Streams the assistant's reply. Thinking blocks (<think>…</think>) are filtered out.
    func stream(_ messages: [Message], system: String? = nil, maxTokens: Int = 700, temperature: Double = 0.4) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let base else { throw URLError(.badURL) }
                if status != .ready { status = .loading }
                var all: [Message] = []
                if let system { all.append(Message(role: "system", content: system)) }
                all += messages
                var req = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
                req.httpMethod = "POST"
                req.timeoutInterval = 300
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "messages": all.map { ["role": $0.role, "content": $0.content] },
                    "max_tokens": maxTokens,
                    "temperature": temperature,
                    "stream": true,
                    "chat_template_kwargs": ["enable_thinking": false],
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                var thinking = false
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choice = (obj["choices"] as? [[String: Any]])?.first,
                          let delta = choice["delta"] as? [String: Any],
                          var piece = delta["content"] as? String, !piece.isEmpty else { continue }
                    if status != .ready { status = .ready }
                    // Drop any reasoning the model emits anyway.
                    if piece.contains("<think>") { thinking = true; piece = piece.components(separatedBy: "<think>").first ?? "" }
                    if thinking {
                        guard piece.contains("</think>") || line.contains("</think>") else { continue }
                        thinking = false
                        piece = piece.components(separatedBy: "</think>").last ?? ""
                    }
                    if !piece.isEmpty { continuation.yield(piece) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
            Task {
                do { _ = try await task.value } catch { continuation.finish(throwing: error) }
            }
        }
    }

    /// Whole reply at once (used for report summaries).
    func complete(_ prompt: String, system: String? = nil, maxTokens: Int = 500) async throws -> String {
        var text = ""
        for try await piece in stream([Message(role: "user", content: prompt)], system: system, maxTokens: maxTokens, temperature: 0.3) {
            text += piece
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var defaultSystemPrompt: String {
        tr("你是 MacIsle 里的本地助手，运行在用户自己的 Mac 上。回答简洁、直接、准确；默认用中文，必要时保留英文术语；不确定就说明。",
           "You are the local assistant inside MacIsle, running on the user's own Mac. Be concise, direct and accurate; say so when unsure.")
    }
}

// MARK: - Conversation in the "Ask AI" card

@MainActor
final class AskSession: ObservableObject {
    static let shared = AskSession()

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var answer: String
        var label: String?        // e.g. "翻译剪贴板"
        var failed = false
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var isRunning = false
    @Published var draft = ""

    private var task: Task<Void, Never>?

    var current: Turn? { turns.last }

    /// - Parameters:
    ///   - question: what is sent to the model
    ///   - label: short title shown instead of a long prompt (clipboard actions)
    func ask(_ question: String, label: String? = nil, keepHistory: Bool = true) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        task?.cancel()
        if !keepHistory { turns.removeAll() }
        // Short memory: the last 3 exchanges.
        let history = turns.suffix(3).flatMap { [LocalAI.Message(role: "user", content: $0.question),
                                                 LocalAI.Message(role: "assistant", content: $0.answer)] }
        turns.append(Turn(question: q, answer: "", label: label))
        if turns.count > 12 { turns.removeFirst(turns.count - 12) }
        isRunning = true
        task = Task {
            do {
                for try await piece in LocalAI.shared.stream(history + [LocalAI.Message(role: "user", content: q)],
                                                             system: LocalAI.defaultSystemPrompt) {
                    guard !Task.isCancelled else { break }
                    if var last = turns.last { last.answer += piece; turns[turns.count - 1] = last }
                }
            } catch {
                if var last = turns.last {
                    last.failed = true
                    if last.answer.isEmpty {
                        last.answer = tr("没有连上本地模型。请在设置 › 本地 AI 里查看状态，或运行 scripts/connect-local-ai.sh。",
                                         "Couldn't reach the local model. Check Settings › Local AI, or run scripts/connect-local-ai.sh.")
                    }
                    turns[turns.count - 1] = last
                }
            }
            isRunning = false
            if IslandUIState.shared.tab != .ask { IslandUIState.shared.flash(.copied(tr("AI 回答好了", "AI answer ready")), duration: 2) }
        }
    }

    func stop() {
        task?.cancel()
        isRunning = false
    }

    func clear() {
        stop()
        turns.removeAll()
    }

    // MARK: Clipboard actions

    enum Action: String, CaseIterable, Identifiable {
        case translate, summarize, polish, explain
        var id: String { rawValue }

        var title: String {
            switch self {
            case .translate: return tr("翻译", "Translate")
            case .summarize: return tr("总结", "Summarize")
            case .polish: return tr("润色", "Polish")
            case .explain: return tr("解释", "Explain")
            }
        }

        var symbol: String {
            switch self {
            case .translate: return "character.bubble"
            case .summarize: return "text.badge.star"
            case .polish: return "wand.and.stars"
            case .explain: return "lightbulb"
            }
        }

        func prompt(for text: String) -> String {
            let snippet = String(text.prefix(6000))
            let chinese = snippet.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count > snippet.count / 6
            switch self {
            case .translate:
                return chinese
                    ? "Translate the following into natural English. Output only the translation.\n\n\(snippet)"
                    : "把下面的内容翻译成自然流畅的简体中文，只输出译文。\n\n\(snippet)"
            case .summarize:
                return tr("用不超过 3 条要点总结下面的内容：\n\n", "Summarize the following in at most 3 bullet points:\n\n") + snippet
            case .polish:
                return tr("润色下面这段文字：保持原意和语言，表达更自然专业，只输出改好的文字。\n\n",
                          "Polish the following text: keep its meaning and language, make it clearer and more natural. Output only the result.\n\n") + snippet
            case .explain:
                return tr("解释下面的内容（如果是代码或报错，说明它在做什么、哪里可能有问题、怎么改），简洁：\n\n",
                          "Explain the following concisely (if it's code or an error: what it does, what's likely wrong, how to fix it):\n\n") + snippet
            }
        }
    }

    func run(_ action: Action, on text: String) {
        ask(action.prompt(for: text), label: "\(action.title) · \(text.prefix(24).replacingOccurrences(of: "\n", with: " "))", keepHistory: false)
        withAnimation(IslandMotion.page) { IslandUIState.shared.tab = .ask }
    }
}
