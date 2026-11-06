//
//  DossierReport.swift
//  boringNotch – Dynamic Island skin
//
//  Builds the "客户资料整理" document (HTML → NSAttributedString → .docx, opens in Word/Pages).
//

import AppKit
import Foundation

enum DossierReport {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func html(folder: String, documents: [DossierDocument], fields: [DossierField], startedAt: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        let ocrCount = documents.filter(\.usedOCR).count
        let pending = fields.filter(\.needsConfirmation)
        let conflicts = fields.filter { $0.variants.count > 1 && $0.kind.isIdentity }
        let failed = documents.filter { $0.error != nil }

        var h = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: 'PingFang SC', 'Helvetica Neue', sans-serif; font-size: 11pt; color: #1d1d1f; }
        h1 { font-size: 20pt; margin-bottom: 2pt; }
        h2 { font-size: 14pt; margin-top: 18pt; border-bottom: 1px solid #d2d2d7; padding-bottom: 3pt; }
        h3 { font-size: 12pt; margin-top: 12pt; }
        .meta { color: #6e6e73; font-size: 10pt; }
        table { border-collapse: collapse; width: 100%; }
        td, th { border: 1px solid #d2d2d7; padding: 4pt 6pt; vertical-align: top; font-size: 10pt; }
        th { background: #f2f2f7; text-align: left; }
        .ok { color: #1a7f37; } .warn { color: #b25000; } .bad { color: #c62828; }
        pre { font-family: 'PingFang SC', monospace; font-size: 9pt; white-space: pre-wrap; color: #3a3a3c; }
        </style></head><body>
        <h1>\(esc(folder)) · 客户资料整理</h1>
        <p class="meta">生成时间：\(f.string(from: .now)) · 共 \(documents.count) 份文件（其中 \(ocrCount) 份经 OCR 识别）· 全程本机处理</p>
        """

        // 1. Overview
        h += "<h2>一、概览</h2><table><tr><th>类别</th><th>数量</th><th>文件</th></tr>"
        for c in DossierCategory.allCases {
            let docs = documents.filter { $0.category == c }
            guard !docs.isEmpty else { continue }
            h += "<tr><td>\(c.title)</td><td>\(docs.count)</td><td>\(docs.map { esc($0.name) }.joined(separator: "<br>"))</td></tr>"
        }
        h += "</table>"
        h += "<p>核对结论："
        if conflicts.isEmpty {
            h += "<span class=\"ok\">各文件之间的关键信息一致。</span>"
        } else {
            h += "<span class=\"warn\">\(conflicts.count) 项关键信息在不同文件中写法不同</span>，"
            h += pending.isEmpty ? "已全部人工确认。" : "<span class=\"bad\">其中 \(pending.count) 项尚未确认</span>，见第三部分。"
        }
        if !failed.isEmpty { h += " \(failed.count) 份文件未能识别出文字。" }
        h += "</p>"

        // 2. Key facts
        h += "<h2>二、关键信息（交叉核对）</h2><table><tr><th>项目</th><th>内容</th><th>来源</th><th>状态</th></tr>"
        for field in fields {
            let value: String
            let status: String
            if let resolved = field.resolvedValue {
                value = esc(resolved)
                if field.variants.count == 1 {
                    status = field.variants[0].sources.count > 1 ? "<span class=\"ok\">\(field.variants[0].sources.count) 份文件一致</span>" : "单一来源"
                } else {
                    status = "<span class=\"ok\">已人工确认</span>"
                }
            } else if field.kind.isIdentity {
                value = field.variants.map { esc($0.value) }.joined(separator: "<br>")
                status = "<span class=\"bad\">待确认\(field.looksLikeOCRSlip ? "（疑似识别误差）" : "")</span>"
            } else {
                value = field.variants.map { esc($0.value) }.joined(separator: "<br>")
                status = "共 \(field.variants.count) 个"
            }
            let sources = field.variants.flatMap(\.sources)
            let uniqueSources = Array(NSOrderedSet(array: sources)) as? [String] ?? sources
            h += "<tr><td>\(field.kind.title)</td><td>\(value)</td><td>\(uniqueSources.prefix(4).map(esc).joined(separator: "<br>"))\(uniqueSources.count > 4 ? "<br>等 \(uniqueSources.count) 份" : "")</td><td>\(status)</td></tr>"
        }
        h += "</table>"

        // 3. Differences
        h += "<h2>三、差异与待确认事项</h2>"
        if conflicts.isEmpty {
            h += "<p class=\"ok\">无。</p>"
        } else {
            for field in conflicts {
                h += "<h3>\(field.kind.title)\(field.chosen != nil ? " <span class=\"ok\">✓ 已确认为「\(esc(field.chosen!))」</span>" : "")</h3><ul>"
                for v in field.variants {
                    h += "<li>「\(esc(v.value))」— 出现在：\(v.sources.map(esc).joined(separator: "、"))</li>"
                }
                h += "</ul>"
                if field.looksLikeOCRSlip { h += "<p class=\"meta\">有两种写法只差一个字符，可能是扫描件识别误差，建议对照原件。</p>" }
            }
        }

        // 4. Per-category detail
        h += "<h2>四、分类明细</h2>"
        for c in DossierCategory.allCases {
            let docs = documents.filter { $0.category == c }
            guard !docs.isEmpty else { continue }
            h += "<h3>\(c.title)（\(docs.count)）</h3><table><tr><th>文件</th><th>提取信息</th><th>日期 / 金额</th></tr>"
            for d in docs {
                let info = d.hits.prefix(8).map { "\($0.kind.title)：\(esc($0.value))" }.joined(separator: "<br>")
                let extra = (d.dates.prefix(3) + d.amounts.prefix(3)).map(esc).joined(separator: "<br>")
                let note = d.error.map { "<br><span class=\"bad\">\(esc($0))</span>" } ?? ""
                h += "<tr><td>\(esc(d.relativePath))\(d.usedOCR ? "<br><span class=\"meta\">OCR</span>" : "")\(note)</td><td>\(info.isEmpty ? esc(String(d.gist.prefix(80))) : info)</td><td>\(extra)</td></tr>"
            }
            h += "</table>"
        }

        // 5. Appendix
        h += "<h2>附录：识别全文</h2>"
        for d in documents where !d.text.isEmpty {
            h += "<h3>\(esc(d.relativePath))</h3><pre>\(esc(String(d.text.prefix(6000))))\(d.text.count > 6000 ? "\n……（已截断）" : "")</pre>"
        }
        h += "</body></html>"
        return h
    }

    /// Writes ~/Downloads/客户资料整理/<folder> 资料整理 <time>.docx
    @MainActor
    static func writeDocx(html: String, folder: String) throws -> URL {
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { throw NSError(domain: "Dossier", code: 10, userInfo: [NSLocalizedDescriptionKey: "排版失败"]) }

        let docx = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML,
                                                            .title: "\(folder) 客户资料整理"])
        let downloads = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")).resolvingSymlinksInPath()
        let dir = downloads.appendingPathComponent("客户资料整理", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "MMdd-HHmmss"
        let safe = folder.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("\(safe) 资料整理 \(stamp.string(from: .now)).docx")
        try docx.write(to: url)
        return url
    }
}
