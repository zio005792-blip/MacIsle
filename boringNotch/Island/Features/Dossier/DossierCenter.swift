//
//  DossierCenter.swift
//  MacIsle
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
    @Published private(set) var diff: DossierDiff?
    @Published private(set) var redactedFolder: URL?
    @AppStorage("island.dossier.checklist") var checklistKindRaw: String = DossierChecklistKind.app.rawValue

    var checklistKind: DossierChecklistKind {
        get { DossierChecklistKind(rawValue: checklistKindRaw) ?? .app }
        set { checklistKindRaw = newValue.rawValue; objectWillChange.send() }
    }

    var checklist: [DossierChecklistItem] { DossierExtractor.checklist(checklistKind, documents: documents) }
    var missingRequired: [DossierChecklistItem] { checklist.filter { $0.required && !$0.present } }

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
        diff = nil
        redactedFolder = nil
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
            results = DossierExtractor.reconcileTransactionParties(results)
            let compared = DossierExtractor.compare(results)
            await self?.finishScan(results, compared)
        }
    }

    nonisolated private static func process(_ url: URL, relativePath: String) -> DossierDocument {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do {
            let r = try DossierExtractor.read(url)
            let category = DossierExtractor.classify(text: r.text, fileName: url.lastPathComponent, imageAspect: r.imageAspect)
            return DossierDocument(
                id: UUID(), relativePath: relativePath, fileSize: size,
                facts: DossierExtractor.extractFacts(from: r.text, category: category),
                redactions: r.redactions,
                category: category,
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
        // Compare with the last time this client was processed, then remember this version.
        let key = historyKey()
        if let previous = DossierHistory.load()[key] { diff = DossierHistory.diff(previous, docs, compared) }
        DossierHistory.save(key: key, folder: folderName, documents: docs, fields: compared)
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
        diff = nil
        redactedFolder = nil
    }

    // MARK: Export

    private func historyKey() -> String {
        fields.first(where: { $0.kind == .entityName })?.variants.first?.value ?? folderName
    }

    private var reportContext: DossierReport.Context {
        DossierReport.Context(folder: folderName, documents: documents, fields: fields, startedAt: startedAt ?? .now,
                              checklistKind: checklistKind, checklist: checklist, diff: diff)
    }

    /// 打码版: a masked report plus copies of every image / PDF with ID, phone and card numbers blacked out.
    func exportRedacted() {
        guard !documents.isEmpty else { return }
        phase = .exporting
        let access = folderURL?.startAccessingSecurityScopedResource() ?? false
        defer { if access { folderURL?.stopAccessingSecurityScopedResource() } }
        do {
            let html = DossierReport.html(reportContext, masked: true)
            let report = try DossierReport.writeDocx(html: html, folder: folderName, suffix: "打码版")
            let dir = report.deletingLastPathComponent()
                .appendingPathComponent(report.deletingPathExtension().lastPathComponent + " 附件", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var isDir: ObjCBool = false
            let root: URL? = folderURL.flatMap { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue ? $0 : $0.deletingLastPathComponent() }
            for doc in documents where !doc.redactions.isEmpty {
                guard let root else { break }
                DossierRedactor.redact(source: root.appendingPathComponent(doc.relativePath), doc: doc, into: dir)
            }
            redactedFolder = dir
            phase = .finished(report)
            NSWorkspace.shared.activateFileViewerSelecting([report, dir])
        } catch {
            phase = .failed("生成打码版失败：\(error.localizedDescription)")
        }
    }

    func export() {
        guard !documents.isEmpty else { return }
        phase = .exporting
        let html = DossierReport.html(reportContext, masked: false)
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
