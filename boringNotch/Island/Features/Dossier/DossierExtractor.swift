//
//  DossierExtractor.swift
//  boringNotch – Dynamic Island skin
//
//  On-device text extraction (Vision OCR, PDF text layer, Office/RTF/plain text),
//  rule-based classification, field extraction and cross-document comparison.
//  Nothing leaves the Mac.
//

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

enum DossierExtractor {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]
    static let textExtensions: Set<String> = ["txt", "md", "rtf", "rtfd", "doc", "docx", "html", "htm", "odt", "csv"]
    static let maxFiles = 300
    static let maxPDFPages = 40

    /// Every readable file inside a folder (recursively), skipping hidden files and bundles.
    static func collectFiles(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in e {
            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) || textExtensions.contains(ext) || ext == "pdf" else { continue }
            files.append(url)
            if files.count >= maxFiles { break }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Reading

    struct ReadResult {
        var text: String
        var pages: Int
        var usedOCR: Bool
        var imageAspect: CGFloat?
    }

    static func read(_ url: URL) throws -> ReadResult {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "Dossier", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开图片"])
            }
            return ReadResult(text: try ocr(image), pages: 1, usedOCR: true,
                              imageAspect: CGFloat(image.height) / CGFloat(max(image.width, 1)))
        }
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else {
                throw NSError(domain: "Dossier", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法打开 PDF"])
            }
            var parts: [String] = []
            var usedOCR = false
            for i in 0..<min(pdf.pageCount, maxPDFPages) {
                guard let page = pdf.page(at: i) else { continue }
                let layer = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if layer.count >= 20 {
                    parts.append(layer)
                } else if let image = render(page) {
                    // Scanned page: no text layer, OCR it.
                    parts.append(try ocr(image))
                    usedOCR = true
                }
            }
            return ReadResult(text: parts.joined(separator: "\n\n"), pages: pdf.pageCount, usedOCR: usedOCR, imageAspect: nil)
        }
        // Office / RTF / HTML / plain text through AppKit's document readers.
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return ReadResult(text: attributed.string, pages: 1, usedOCR: false, imageAspect: nil)
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .init(rawValue: 0x80000632))) ?? ""
        return ReadResult(text: text, pages: 1, usedOCR: false, imageAspect: nil)
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = min(3, 2200 / max(bounds.width, bounds.height, 1))
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Vision OCR (Simplified/Traditional Chinese + English), lines in reading order.
    static func ocr(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = (request.results ?? [])
        // Sort top-to-bottom, then left-to-right, grouping items on roughly the same line.
        let sorted = observations.sorted { a, b in
            let ay = a.boundingBox.midY, by = b.boundingBox.midY
            if abs(ay - by) > 0.012 { return ay > by }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        var lines: [String] = []
        var current = ""
        var lastY: CGFloat?
        for o in sorted {
            guard let s = o.topCandidates(1).first?.string else { continue }
            if let y = lastY, abs(y - o.boundingBox.midY) <= 0.012 {
                current += " " + s
            } else {
                if !current.isEmpty { lines.append(current) }
                current = s
            }
            lastY = o.boundingBox.midY
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    // MARK: Classification

    static func classify(text: String, fileName: String, imageAspect: CGFloat?) -> DossierCategory {
        let haystack = fileName + "\n" + text
        var best: (DossierCategory, Double) = (.other, 0)
        for c in DossierCategory.allCases {
            var score = 0.0
            for (word, weight) in c.keywords {
                if fileName.contains(word) { score += weight * 1.5 }
                let count = haystack.components(separatedBy: word).count - 1
                score += Double(min(count, 3)) * weight
            }
            if score > best.1 { best = (c, score) }
        }
        if best.1 >= 4 { return best.0 }
        // Tall images with little document-like text are app screenshots.
        if let aspect = imageAspect, aspect > 1.7 || aspect < 0.6 { return .screenshot }
        if fileName.lowercased().contains("screenshot") || fileName.contains("截图") || fileName.contains("截屏") { return .screenshot }
        return best.1 >= 2 ? best.0 : .other
    }

    // MARK: Field extraction

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let r = m.range(at: group)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// Full-width → half-width, unified brackets, no stray spaces. Used for display *and* comparison.
    static func normalize(_ s: String) -> String {
        var out = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        out = out.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
        out = out.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return out.trimmingCharacters(in: CharacterSet(charactersIn: ":：,，。;；、"))
    }

    static func extractHits(from raw: String) -> [DossierHit] {
        let text = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        var hits: [DossierHit] = []
        func add(_ kind: DossierFieldKind, _ values: [String]) {
            for v in values {
                let n = normalize(v)
                guard !n.isEmpty, !hits.contains(DossierHit(kind: kind, value: n)) else { continue }
                hits.append(DossierHit(kind: kind, value: n))
            }
        }

        // Organisations, split into the client (entity) and the service side (乙方 / 被授权方 – usually you).
        for (name, context) in organisations(in: text) {
            let isCounterparty = ["乙方", "受托方", "被授权", "兹授权", "服务方", "开发方", "承接方"].contains { context.contains($0) }
            add(isCounterparty ? .counterparty : .entityName, [name])
        }
        add(.creditCode, matches(#"(?<![0-9A-Z])[0-9A-HJ-NPQRTUWXY]{2}\d{6}[0-9A-HJ-NPQRTUWXY]{10}(?![0-9A-Z])"#, in: text.uppercased())
            .filter { code in
                validCreditCode(code) ||
                // Keep near-misses (one OCR slip breaks the checksum) only when they look like a real registration code.
                (code.contains(where: \.isLetter) && ["91", "92", "93", "11", "12", "13", "19", "51", "52", "53", "59", "71", "72", "81", "89"].contains(String(code.prefix(2))))
            })
        add(.legalRep, matches(#"(?:法定代表人|法人代表|负责人)\s*[:：]?\s*([\p{Han}]{2,4})"#, in: text, group: 1))
        add(.personName, matches(#"(?:姓\s*名|联系人|经办人|签字人)\s*[:：]?\s*([\p{Han}]{2,4})"#, in: text, group: 1))
        add(.idNumber, matches(#"(?<!\d)[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?![\dXx])"#, in: text)
            .map { $0.uppercased() }.filter(validIDNumber))
        add(.phone, matches(#"(?<!\d)1[3-9]\d{9}(?!\d)"#, in: text))
        add(.email, matches(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text).map { $0.lowercased() })
        add(.address, matches(#"(?:住所|地址|住址|经营场所|通讯地址)\s*[:：]?\s*([\p{Han}A-Za-z0-9()（）#\-号室栋楼层路街道区县市省]{6,60})"#, in: text, group: 1))
        add(.appName, matches(#"《([^》\n]{1,30})》"#, in: text, group: 1).filter { !$0.contains("法") && !$0.contains("条例") && !$0.contains("协议") })
        add(.appName, matches(#"(?:应用名称|软件名称|App\s*名称|产品名称)\s*[:：]?\s*([^\s,，。;；]{1,30})"#, in: text, group: 1))
        add(.bankAccount, matches(#"(?:账号|帐号|银行账户|卡号)\s*[:：]?\s*(\d[\d ]{10,30}\d)"#, in: text, group: 1))
        add(.website, matches(#"(?:https?://)?(?:www\.)?[A-Za-z0-9-]+\.(?:com|cn|net|org|io|app|com\.cn)(?:/[^\s，。]*)?"#, in: text)
            .map { $0.lowercased() }.filter { !$0.contains("@") })
        return hits
    }

    /// Organisation names with the text just before them (for role detection), with leading
    /// sentence noise ("本应用由…", "授权方：…") trimmed off.
    static func organisations(in text: String) -> [(String, String)] {
        let pattern = #"[\p{Han}A-Za-z0-9()（）·]{2,40}?(?:股份有限公司|有限责任公司|有限公司|集团|工作室|事务所|合作社|分公司|研究院)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let separators = ["授权方", "被授权", "兹授权", "甲方", "乙方", "名称", "运营方", "运营", "关于", "本应用由", "我司", "特此",
                          "由", "向", "被", "经", "兹", "：", ":"]   // single characters that never start a company name
        var out: [(String, String)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var name = ns.substring(with: m.range)
            var consumedPrefix = ""
            // Cut at the last separator so only the organisation itself remains.
            var cut = true
            while cut {
                cut = false
                for sep in separators {
                    if let r = name.range(of: sep, options: .backwards), r.upperBound < name.endIndex,
                       name.distance(from: r.upperBound, to: name.endIndex) >= 4 {
                        consumedPrefix += String(name[..<r.upperBound])
                        name = String(name[r.upperBound...])
                        cut = true
                        break
                    }
                }
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "()（）· "))
            guard name.count >= 4, !name.hasPrefix("的"), !name.contains("名称") else { continue }
            let start = max(0, m.range.location - 12)
            let before = ns.substring(with: NSRange(location: start, length: m.range.location - start))
            out.append((name, before + consumedPrefix))
        }
        return out
    }

    static func extractDates(from text: String) -> [String] {
        Array(Set(matches(#"(?:19|20)\d{2}\s*[年\-/.]\s*\d{1,2}\s*[月\-/.]\s*\d{1,2}\s*日?"#, in: text).map(normalize))).sorted()
    }

    static func extractAmounts(from text: String) -> [String] {
        Array(Set(matches(#"(?:[¥￥]\s?\d[\d,]*(?:\.\d{1,2})?|\d[\d,]*(?:\.\d{1,2})?\s?(?:万元|元))"#, in: text).map(normalize))).sorted()
    }

    // MARK: Validators (cut OCR noise)

    static func validIDNumber(_ id: String) -> Bool {
        let chars = Array(id)
        guard chars.count == 18 else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        var sum = 0
        for i in 0..<17 {
            guard let d = chars[i].wholeNumberValue else { return false }
            sum += d * weights[i]
        }
        return checks[sum % 11] == chars[17]
    }

    static func validCreditCode(_ code: String) -> Bool {
        let alphabet = Array("0123456789ABCDEFGHJKLMNPQRTUWXY")
        let weights = [1, 3, 9, 27, 19, 26, 16, 17, 20, 29, 25, 13, 8, 24, 10, 30, 28]
        let chars = Array(code)
        guard chars.count == 18 else { return false }
        var sum = 0
        for i in 0..<17 {
            guard let v = alphabet.firstIndex(of: chars[i]) else { return false }
            sum += v * weights[i]
        }
        let c = (31 - sum % 31) % 31
        return alphabet[c] == chars[17]
    }

    // MARK: Comparison

    /// Groups each field's values across documents; values that are equal after normalisation merge,
    /// values one edit apart are kept separate but flagged as a likely OCR slip.
    static func compare(_ documents: [DossierDocument]) -> [DossierField] {
        var result: [DossierField] = []
        for kind in DossierFieldKind.allCases {
            var variants: [DossierField.Variant] = []
            for doc in documents {
                for hit in doc.hits where hit.kind == kind {
                    if let i = variants.firstIndex(where: { $0.value == hit.value }) {
                        if !variants[i].sources.contains(doc.name) { variants[i].sources.append(doc.name) }
                    } else {
                        variants.append(.init(value: hit.value, sources: [doc.name]))
                    }
                }
            }
            guard !variants.isEmpty else { continue }
            variants.sort { $0.sources.count > $1.sources.count }
            // Person-like fields legitimately hold several different people; keep the top few.
            if !kind.isIdentity || kind == .legalRep { variants = Array(variants.prefix(kind == .legalRep ? 3 : 4)) }
            var slip = false
            if variants.count > 1 {
                for i in 0..<variants.count {
                    for j in (i + 1)..<variants.count where editDistance(variants[i].value, variants[j].value) == 1 {
                        slip = true
                    }
                }
            }
            result.append(DossierField(kind: kind, variants: variants, looksLikeOCRSlip: slip, chosen: nil))
        }
        return result
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 2 else { return 99 }
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
