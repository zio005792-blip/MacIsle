//
//  DossierCenter.swift
//  boringNotch – Dynamic Island skin
//
//  Drop a client folder → OCR every file → classify → extract → cross-check → you confirm
//  the conflicts on the island → a tidy Word document lands in ~/Downloads/客户资料整理/.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DossierCenter: ObservableObject {
    static let shared = DossierCenter()

    enum Phase: Equatable {
        case idle
        case scanning(done: Int, total: Int, current: String)
        case review
        case exporting
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var folderName = ""
    @Published private(set) var documents: [DossierDocument] = []
    @Published private(set) var fields: [DossierField] = []
    @Published private(set) var startedAt: Date?

    private var folderURL: URL?
    private var scanTask: Task<Void, Never>?

    var isBusy: Bool {
        if case .scanning = phase { return true }
        return phase == .exporting
    }

    var progress: Double {
        if case .scanning(let done, let total, _) = phase, total > 0 { return Double(done) / Double(total) }
        return phase == .idle ? 0 : 1
    }

    var pendingConfirmations: [DossierField] { fields.filter(\.needsConfirmation) }

    var categoryCounts: [(DossierCategory, Int)] {
        DossierCategory.allCases.compactMap { c in
            let n = documents.filter { $0.category == c }.count
            return n > 0 ? (c, n) : nil
        }
    }

    // MARK: Intake

    func pickFolder() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要整理的客户资料文件夹"
        panel.prompt = "开始整理"
        let response = panel.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .OK, let url = panel.url { start(folder: url) }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in self.start(folder: url) }
        }
        return true
    }

    func start(folder: URL) {
        scanTask?.cancel()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)

        let access = folder.startAccessingSecurityScopedResource()
        folderURL = folder
        folderName = isDir.boolValue ? folder.lastPathComponent : folder.deletingPathExtension().lastPathComponent
        documents = []
        fields = []
        startedAt = .now
        phase = .scanning(done: 0, total: 0, current: "正在查找文件…")

        let root = isDir.boolValue ? folder : folder.deletingLastPathComponent()
        let single = isDir.boolValue ? nil : folder

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let files = single.map { [$0] } ?? DossierExtractor.collectFiles(in: root)
            guard !files.isEmpty else {
                await self?.fail("文件夹里没有可识别的图片、PDF 或文档")
                return
            }
            var results: [DossierDocument] = []
            for (i, url) in files.enumerated() {
                if Task.isCancelled { return }
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                await self?.report(done: i, total: files.count, current: url.lastPathComponent)
                results.append(Self.process(url, relativePath: rel))
            }
            let compared = DossierExtractor.compare(results)
            await self?.finishScan(results, compared)
        }
    }

    nonisolated private static func process(_ url: URL, relativePath: String) -> DossierDocument {
        do {
            let r = try DossierExtractor.read(url)
            return DossierDocument(
                id: UUID(), relativePath: relativePath,
                category: DossierExtractor.classify(text: r.text, fileName: url.lastPathComponent, imageAspect: r.imageAspect),
                text: r.text, pageCount: r.pages, usedOCR: r.usedOCR,
                hits: DossierExtractor.extractHits(from: r.text),
                dates: DossierExtractor.extractDates(from: r.text),
                amounts: DossierExtractor.extractAmounts(from: r.text),
                error: r.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未识别到文字" : nil)
        } catch {
            return DossierDocument(id: UUID(), relativePath: relativePath, category: .other, text: "", pageCount: 0,
                                   usedOCR: false, hits: [], dates: [], amounts: [], error: error.localizedDescription)
        }
    }

    private func report(done: Int, total: Int, current: String) {
        phase = .scanning(done: done, total: total, current: current)
    }

    private func fail(_ message: String) {
        phase = .failed(message)
    }

    private func finishScan(_ docs: [DossierDocument], _ compared: [DossierField]) {
        documents = docs
        fields = compared
        phase = .review
        let pending = pendingConfirmations.count
        IslandUIState.shared.flash(.dossier, duration: 4.5)
        NSSound(named: pending > 0 ? "Tink" : "Glass")?.play()
    }

    // MARK: Review

    func choose(_ value: String, for kind: DossierFieldKind) {
        guard let i = fields.firstIndex(where: { $0.kind == kind }) else { return }
        fields[i].chosen = fields[i].chosen == value ? nil : value
    }

    func acceptMajorityForAll() {
        for i in fields.indices where fields[i].needsConfirmation {
            fields[i].chosen = fields[i].variants.first?.value
        }
    }

    func reset() {
        scanTask?.cancel()
        phase = .idle
        documents = []
        fields = []
        folderName = ""
    }

    // MARK: Export

    func export() {
        guard !documents.isEmpty else { return }
        phase = .exporting
        let html = DossierReport.html(folder: folderName, documents: documents, fields: fields, startedAt: startedAt ?? .now)
        do {
            let url = try DossierReport.writeDocx(html: html, folder: folderName)
            phase = .finished(url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            phase = .failed("生成文档失败：\(error.localizedDescription)")
        }
    }

    func openResult() {
        if case .finished(let url) = phase { NSWorkspace.shared.open(url) }
    }
}
