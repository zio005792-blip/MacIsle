//
//  DossierReport.swift
//  MacIsle
//
//  Builds the "客户资料整理" document (HTML → NSAttributedString → .docx, opens in Word/Pages).
//  `masked: true` produces the shareable 打码版 (ID / card / phone numbers hidden everywhere).
//

import AppKit
import Foundation

enum DossierReport {
    struct Context {
        let folder: String
        let documents: [DossierDocument]
        let fields: [DossierField]
        let startedAt: Date
        let checklistKind: DossierChecklistKind
        let checklist: [DossierChecklistItem]
        let diff: DossierDiff?
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Hides every sensitive number in free text.
    private static func maskText(_ s: String) -> String {
        var out = s
        for pattern in DossierExtractor.sensitivePatterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let v = ns.substring(with: m.range)
                let kept = v.count > 7 ? String(v.prefix(3)) + String(repeating: "•", count: v.count - 7) + String(v.suffix(4)) : String(repeating: "•", count: v.count)
                out = (out as NSString).replacingCharacters(in: m.range, with: kept)
            }
        }
        return out
    }

    static func html(_ c: Context, masked: Bool) -> String {
        let show: (DossierFieldKind, String) -> String = { kind, value in esc(masked ? kind.masked(value) : value) }
        let text: (String) -> String = { esc(masked ? maskText($0) : $0) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        let documents = c.documents, fields = c.fields
        let ocrCount = documents.filter(\.usedOCR).count
        let pending = fields.filter(\.needsConfirmation)
        let conflicts = fields.filter { $0.variants.count > 1 && $0.kind.isIdentity }
        let failed = documents.filter { $0.error != nil }
        let missing = c.checklist.filter { $0.required && !$0.present }

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
        <h1>\(esc(c.folder)) · 客户资料整理\(masked ? "（打码版）" : "")</h1>
        <p class="meta">生成时间：\(f.string(from: .now)) · 共 \(documents.count) 份文件（其中 \(ocrCount) 份经 OCR 识别）· 全程本机处理\(masked ? " · 身份证号、银行卡号、手机号已隐藏" : "")</p>
        """

        // 1. Overview
        h += "<h2>一、概览</h2><table><tr><th>类别</th><th>数量</th><th>文件</th></tr>"
        for cat in DossierCategory.allCases {
            let docs = documents.filter { $0.category == cat }
            guard !docs.isEmpty else { continue }
            h += "<tr><td>\(cat.title)</td><td>\(docs.count)</td><td>\(docs.map { esc($0.name) }.joined(separator: "<br>"))</td></tr>"
        }
        h += "</table><p>核对结论："
        if conflicts.isEmpty {
            h += "<span class=\"ok\">各文件之间的关键信息一致。</span>"
        } else {
            h += "<span class=\"warn\">\(conflicts.count) 项关键信息在不同文件中写法不同</span>，"
            h += pending.isEmpty ? "已全部人工确认。" : "<span class=\"bad\">其中 \(pending.count) 项尚未确认</span>，见第三部分。"
        }
        if !failed.isEmpty { h += " \(failed.count) 份文件未能识别出文字。" }
        if c.checklistKind != .none {
            h += missing.isEmpty ? " <span class=\"ok\">\(c.checklistKind.title)必备材料齐全。</span>"
                                 : " <span class=\"bad\">\(c.checklistKind.title)缺少：\(missing.map(\.title).joined(separator: "、"))。</span>"
        }
        if let d = c.diff { h += " 与 \(f.string(from: d.previousDate)) 的上一版相比：\(d.summary)。" }
        h += "</p>"

        // 1b. Checklist
        if c.checklistKind != .none {
            h += "<h3>\(c.checklistKind.title)材料清单</h3><table><tr><th>材料</th><th>要求</th><th>状态</th><th>对应文件</th></tr>"
            for item in c.checklist {
                let status = item.present ? "<span class=\"ok\">✓ 已提供</span>" : (item.required ? "<span class=\"bad\">✗ 缺少</span>" : "<span class=\"meta\">未提供</span>")
                h += "<tr><td>\(item.title)</td><td>\(item.required ? "必需" : "按需")</td><td>\(status)</td><td>\(item.satisfiedBy.map(esc).joined(separator: "<br>"))</td></tr>"
            }
            h += "</table>"
        }

        // 2. Key facts
        h += "<h2>二、关键信息（交叉核对）</h2><table><tr><th>项目</th><th>内容</th><th>来源</th><th>状态</th></tr>"
        for field in fields {
            let value: String
            let status: String
            if let resolved = field.resolvedValue {
                value = show(field.kind, resolved)
                if field.variants.count == 1 {
                    status = field.variants[0].sources.count > 1 ? "<span class=\"ok\">\(field.variants[0].sources.count) 份文件一致</span>" : "单一来源"
                } else {
                    status = "<span class=\"ok\">已人工确认</span>"
                }
            } else if field.kind.isIdentity {
                value = field.variants.map { show(field.kind, $0.value) }.joined(separator: "<br>")
                status = "<span class=\"bad\">待确认\(field.looksLikeOCRSlip ? "（疑似识别误差）" : "")</span>"
            } else {
                value = field.variants.map { show(field.kind, $0.value) }.joined(separator: "<br>")
                status = "共 \(field.variants.count) 个"
            }
            let sources = Array(NSOrderedSet(array: field.variants.flatMap(\.sources))) as? [String] ?? []
            h += "<tr><td>\(field.kind.title)</td><td>\(value)</td><td>\(sources.prefix(4).map(esc).joined(separator: "<br>"))\(sources.count > 4 ? "<br>等 \(sources.count) 份" : "")</td><td>\(status)</td></tr>"
        }
        h += "</table>"

        // 3. Differences
        h += "<h2>三、差异与待确认事项</h2>"
        if conflicts.isEmpty {
            h += "<p class=\"ok\">无。</p>"
        } else {
            for field in conflicts {
                h += "<h3>\(field.kind.title)\(field.chosen != nil ? " <span class=\"ok\">✓ 已确认为「\(show(field.kind, field.chosen!))」</span>" : "")</h3><ul>"
                for v in field.variants {
                    h += "<li>「\(show(field.kind, v.value))」— 出现在：\(v.sources.map(esc).joined(separator: "、"))</li>"
                }
                h += "</ul>"
                if field.looksLikeOCRSlip { h += "<p class=\"meta\">有两种写法只差一个字符，可能是扫描件识别误差，建议对照原件。</p>" }
            }
        }

        // 4. Compared with last version
        if let d = c.diff {
            h += "<h2>四、与上一版相比（\(f.string(from: d.previousDate))）</h2>"
            if d.isEmpty {
                h += "<p class=\"ok\">文件和关键信息都没有变化。</p>"
            } else {
                h += "<ul>"
                if !d.added.isEmpty { h += "<li>新增文件：\(d.added.map(esc).joined(separator: "、"))</li>" }
                if !d.removed.isEmpty { h += "<li>删除文件：\(d.removed.map(esc).joined(separator: "、"))</li>" }
                if !d.modified.isEmpty { h += "<li>内容有改动：\(d.modified.map(esc).joined(separator: "、"))</li>" }
                for (kind, old, new) in d.changedFields {
                    h += "<li class=\"warn\">\(kind.title)：「\(show(kind, old))」→「\(show(kind, new))」</li>"
                }
                h += "</ul>"
            }
        }

        // 5. Invoices
        let invoices = documents.filter { $0.category == .invoice }
        if !invoices.isEmpty {
            h += "<h2>发票汇总</h2><table><tr><th>文件</th><th>发票号码</th><th>开票日期</th><th>价税合计</th><th>购买方 / 销售方</th></tr>"
            var total = 0.0
            for d in invoices {
                func fact(_ l: String) -> String { d.facts.first { $0.label == l }?.value ?? "" }
                let amount = fact("价税合计")
                total += Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
                h += "<tr><td>\(esc(d.name))</td><td>\(esc(fact("发票号码")))</td><td>\(esc(fact("开票日期")))</td><td>\(esc(amount))</td><td>\(text(fact("购买方")))<br>\(text(fact("销售方")))</td></tr>"
            }
            h += "<tr><th colspan=\"3\">合计</th><th>\(String(format: "%.2f", total))</th><th></th></tr></table>"
        }

        // 6. Per-category detail
        h += "<h2>分类明细</h2>"
        for cat in DossierCategory.allCases {
            let docs = documents.filter { $0.category == cat }
            guard !docs.isEmpty else { continue }
            h += "<h3>\(cat.title)（\(docs.count)）</h3><table><tr><th>文件</th><th>提取信息</th><th>要素 / 日期 / 金额</th></tr>"
            for d in docs {
                let info = d.hits.prefix(8).map { "\($0.kind.title)：\(show($0.kind, $0.value))" }.joined(separator: "<br>")
                let facts = d.facts.map { "\($0.label)：\(text($0.value))" }
                let extra = (facts + d.dates.prefix(3).map(esc) + d.amounts.prefix(3).map(esc)).joined(separator: "<br>")
                let note = d.error.map { "<br><span class=\"bad\">\(esc($0))</span>" } ?? ""
                h += "<tr><td>\(esc(d.relativePath))\(d.usedOCR ? "<br><span class=\"meta\">OCR</span>" : "")\(note)</td><td>\(info.isEmpty ? text(String(d.gist.prefix(80))) : info)</td><td>\(extra)</td></tr>"
            }
            h += "</table>"
        }

        // 7. Appendix
        h += "<h2>附录：识别全文</h2>"
        for d in documents where !d.text.isEmpty {
            h += "<h3>\(esc(d.relativePath))</h3><pre>\(text(String(d.text.prefix(6000))))\(d.text.count > 6000 ? "\n……（已截断）" : "")</pre>"
        }
        h += "</body></html>"
        return h
    }

    /// Writes ~/Downloads/客户资料整理/<folder> 资料整理[ 打码版] <time>.docx
    @MainActor
    static func writeDocx(html: String, folder: String, suffix: String = "") throws -> URL {
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
        let name = "\(safe) 资料整理\(suffix.isEmpty ? "" : " " + suffix) \(stamp.string(from: .now)).docx"
        let url = dir.appendingPathComponent(name)
        try docx.write(to: url)
        return url
    }
}
