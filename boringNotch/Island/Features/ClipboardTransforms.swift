//
//  ClipboardTransforms.swift
//  MacIsle
//
//  One-tap developer conversions for clipboard text: JSON pretty-print / minify,
//  URL / Base64 decode, Unix timestamp ↔ date, JWT payload, case changes.
//

import Foundation

struct ClipboardTransform: Identifiable {
    let id: String
    let title: String
    let result: String
}

enum ClipboardTransforms {
    static func suggestions(for raw: String) -> [ClipboardTransform] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 200_000 else { return [] }
        var out: [ClipboardTransform] = []

        // JSON
        if let first = text.first, first == "{" || first == "[",
           let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let s = String(data: pretty, encoding: .utf8), s != text {
                out.append(.init(id: "json.pretty", title: "格式化 JSON", result: s))
            }
            if let mini = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]),
               let s = String(data: mini, encoding: .utf8), s != text {
                out.append(.init(id: "json.mini", title: "压缩 JSON", result: s))
            }
        }

        // JWT payload
        let parts = text.split(separator: ".")
        if parts.count == 3, text.hasPrefix("eyJ"), let payload = base64URLDecode(String(parts[1])) {
            out.append(.init(id: "jwt", title: "JWT 内容", result: payload))
        }

        // Unix timestamp (seconds or milliseconds)
        if text.allSatisfy(\.isNumber), (text.count == 10 || text.count == 13), let v = Double(text) {
            let date = Date(timeIntervalSince1970: text.count == 13 ? v / 1000 : v)
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            out.append(.init(id: "ts", title: f.string(from: date), result: f.string(from: date)))
        }

        // Date → timestamp
        if text.count <= 25, let date = parseDate(text) {
            out.append(.init(id: "date.ts", title: "→ 时间戳", result: String(Int(date.timeIntervalSince1970))))
        }

        // URL decode
        if text.contains("%"), let decoded = text.removingPercentEncoding, decoded != text {
            out.append(.init(id: "url.decode", title: "URL 解码", result: decoded))
        }

        // Base64
        if text.count >= 8, text.count % 4 == 0, !text.contains(" "),
           text.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil,
           let data = Data(base64Encoded: text), let s = String(data: data, encoding: .utf8),
           s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }) {
            out.append(.init(id: "b64.decode", title: "Base64 解码", result: s))
        } else if text.count <= 2000, !text.contains("\n") {
            out.append(.init(id: "b64.encode", title: "Base64", result: Data(text.utf8).base64EncodedString()))
        }

        // Plain URL with query → encode is rarely wanted; offer camelCase/snake_case for identifiers.
        if text.count <= 64, text.range(of: "^[A-Za-z][A-Za-z0-9_ -]*$", options: .regularExpression) != nil,
           text.contains(where: { $0 == "_" || $0 == " " || $0 == "-" }) {
            let words = text.split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" }).map { $0.lowercased() }
            let camel = words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.capitalized }.joined()
            out.append(.init(id: "camel", title: camel, result: camel))
        }

        return Array(out.prefix(3))
    }

    private static func base64URLDecode(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
