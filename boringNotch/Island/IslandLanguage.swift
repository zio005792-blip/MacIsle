//
//  IslandLanguage.swift
//  MacIsle
//
//  Chinese / English interface. `tr("中文", "English")` picks the string for the current
//  interface language; `L(_:)` translates fixed strings that travel through data
//  (category names, checklist items). Settings › Language can override the system choice.
//

import AppKit
import Foundation

enum IslandLanguage: String, CaseIterable {
    case system, zh, en

    static let storageKey = "island.language"

    static var preference: IslandLanguage {
        IslandLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Resolved once per launch (switching languages restarts the app).
    static let isEnglish: Bool = {
        switch preference {
        case .en: return true
        case .zh: return false
        case .system: return !(Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }()

    /// Locale for dates, so "Friday, Nov 6" vs "星期五 11月6日" follows the interface.
    static var locale: Locale { isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN") }

    /// Applies a new preference (also for the AppKit / inherited strings) and relaunches.
    static func apply(_ choice: IslandLanguage) {
        UserDefaults.standard.set(choice.rawValue, forKey: storageKey)
        switch choice {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zh: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        ApplicationRelauncher.restart()
    }

    fileprivate static let table: [String: String] = [
        "营业执照": "Business licence", "身份证件": "ID documents", "合同协议": "Contracts",
        "授权 / 承诺函": "Authorisations", "发票票据": "Invoices", "资质证书": "Certificates",
        "银行 / 付款": "Bank / payments", "说明材料": "Explanations", "截图 / 界面": "Screenshots / UI", "其他": "Other",
        "法人身份证": "Representative's ID", "软件著作权证书": "Software copyright certificate",
        "ICP / App 备案": "ICP / App filing", "隐私政策": "Privacy policy", "授权书": "Authorisation letter",
        "情况说明": "Explanation letter", "游戏版号": "Game publishing licence", "防沉迷 / 实名认证": "Anti-addiction / real-name",
        "软著": "copyright cert", "备案": "ICP filing", "防沉迷": "anti-addiction", "身份证": "ID",
    ]
}

/// Interface string in the current language.
@inline(__always)
func tr(_ zh: String, _ en: String) -> String { IslandLanguage.isEnglish ? en : zh }

/// Translates a fixed Chinese string that came from data (falls back to the original).
func L(_ zh: String) -> String {
    guard IslandLanguage.isEnglish else { return zh }
    return IslandLanguage.table[zh] ?? zh
}
