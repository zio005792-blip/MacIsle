//
//  DossierHistory.swift
//  MacIsle
//
//  Remembers the last processed version of each client (file list + resolved key facts,
//  never the full text) so a resubmission can be compared with what came before.
//  Stored in the app's own container: ~/Library/Containers/…/Application Support/dossier-history.json
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum DossierHistory {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dossier-history.json")
    }

    static func load() -> [String: DossierSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: DossierSnapshot].self, from: data)) ?? [:]
    }

    static func save(key: String, folder: String, documents: [DossierDocument], fields: [DossierField]) {
        var all = load()
        var resolved: [String: String] = [:]
        for f in fields {
            if let v = f.resolvedValue ?? f.variants.first?.value { resolved[f.kind.rawValue] = v }
        }
        all[key] = DossierSnapshot(date: .now, folder: folder,
                                   files: Dictionary(documents.map { ($0.relativePath, $0.fileSize) }, uniquingKeysWith: { a, _ in a }),
                                   fields: resolved)
        // Keep the 200 most recent clients.
        if all.count > 200 {
            for k in all.sorted(by: { $0.value.date < $1.value.date }).prefix(all.count - 200).map(\.key) { all.removeValue(forKey: k) }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(all).write(to: url, options: .atomic)
    }

    static func diff(_ old: DossierSnapshot, _ docs: [DossierDocument], _ fields: [DossierField]) -> DossierDiff {
        let now = Dictionary(docs.map { ($0.relativePath, $0.fileSize) }, uniquingKeysWith: { a, _ in a })
        let added = now.keys.filter { old.files[$0] == nil }.sorted()
        let removed = old.files.keys.filter { now[$0] == nil }.sorted()
        let modified = now.compactMap { k, size in old.files[k].flatMap { $0 != size ? k : nil } }.sorted()
        var changed: [(DossierFieldKind, String, String)] = []
        for f in fields {
            guard let new = f.resolvedValue ?? f.variants.first?.value, let prev = old.fields[f.kind.rawValue], prev != new else { continue }
            changed.append((f.kind, prev, new))
        }
        return DossierDiff(previousDate: old.date, added: added, removed: removed, modified: modified, changedFields: changed)
    }
}

/// Writes blacked-out copies of images and PDFs.
enum DossierRedactor {
    static func redact(source: URL, doc: DossierDocument, into dir: URL) {
        let ext = source.pathExtension.lowercased()
        if DossierExtractor.imageExtensions.contains(ext) {
            guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  let out = draw(image, boxes: doc.redactions.filter { $0.page == 0 }.map(\.rect)) else { return }
            let dest = dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "（打码）.png")
            write(out, to: dest)
        } else if ext == "pdf", let pdf = PDFDocument(url: source) {
            // Rasterise every page with boxes burnt in, so nothing can be copied from under the black bars.
            let result = PDFDocument()
            for i in 0..<min(pdf.pageCount, DossierExtractor.maxPDFPages) {
                guard let page = pdf.page(at: i), let image = DossierExtractor.render(page),
                      let out = draw(image, boxes: doc.redactions.filter { $0.page == i }.map(\.rect)),
                      let newPage = PDFPage(image: NSImage(cgImage: out, size: page.bounds(for: .mediaBox).size)) else { continue }
                result.insert(newPage, at: result.pageCount)
            }
            result.write(to: dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "（打码）.pdf"))
        }
    }

    /// Boxes are normalised with a bottom-left origin (Vision / PDF convention).
    private static func draw(_ image: CGImage, boxes: [CGRect]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        for b in boxes {
            let r = CGRect(x: b.minX * CGFloat(w), y: b.minY * CGFloat(h), width: b.width * CGFloat(w), height: b.height * CGFloat(h))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(6, r.height / 4), cornerHeight: min(6, r.height / 4), transform: nil))
            ctx.fillPath()
        }
        return ctx.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
