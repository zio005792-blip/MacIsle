//
//  DossierModels.swift
//  MacIsle
//
//  Data model for "客户资料整理": documents, categories, extracted fields and
//  cross-document comparison results.
//

import Foundation

enum DossierCategory: String, CaseIterable, Codable {
    case businessLicense, idCard, contract, authorization, invoice, qualification, bank, explanation, screenshot, other

    var title: String {
        switch self {
        case .businessLicense: return tr("营业执照", "Business licence")
        case .idCard: return tr("身份证件", "ID documents")
        case .contract: return tr("合同协议", "Contracts")
        case .authorization: return tr("授权 / 承诺函", "Authorisations")
        case .invoice: return tr("发票票据", "Invoices")
        case .qualification: return tr("资质证书", "Certificates")
        case .bank: return tr("银行 / 付款", "Bank / payments")
        case .explanation: return tr("说明材料", "Explanations")
        case .screenshot: return tr("截图 / 界面", "Screenshots / UI")
        case .other: return tr("其他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .businessLicense: return "building.2.fill"
        case .idCard: return "person.text.rectangle.fill"
        case .contract: return "signature"
        case .authorization: return "checkmark.seal.fill"
        case .invoice: return "doc.text.fill"
        case .qualification: return "rosette"
        case .bank: return "creditcard.fill"
        case .explanation: return "text.bubble.fill"
        case .screenshot: return "iphone.gen3"
        case .other: return "folder.fill"
        }
    }

    /// Keyword weights used for classification (title-ish words weigh more).
    var keywords: [(String, Double)] {
        switch self {
        case .businessLicense:
            return [("营业执照", 6), ("统一社会信用代码", 5), ("法定代表人", 3), ("经营范围", 3), ("注册资本", 2), ("成立日期", 2), ("登记机关", 2), ("营业期限", 2)]
        case .idCard:
            return [("居民身份证", 6), ("公民身份号码", 6), ("签发机关", 4), ("有效期限", 2), ("出生", 1.5), ("民族", 2), ("住址", 1)]
        case .contract:
            return [("合同", 4), ("协议", 4), ("甲方", 3), ("乙方", 3), ("违约", 2), ("签订", 2), ("盖章", 1.5), ("签字", 1.5), ("条款", 1.5)]
        case .authorization:
            return [("授权书", 6), ("授权委托", 5), ("承诺函", 6), ("承诺书", 6), ("声明", 3), ("特此", 2), ("郑重承诺", 4), ("授权", 2)]
        case .invoice:
            return [("发票", 5), ("价税合计", 5), ("税额", 3), ("开票", 3), ("购买方", 3), ("销售方", 3), ("收据", 4)]
        case .qualification:
            return [("软件著作权", 6), ("登记证书", 4), ("许可证", 4), ("ICP", 4), ("备案", 3), ("资质", 4), ("证书编号", 3), ("网络文化", 3)]
        case .bank:
            return [("开户行", 5), ("开户银行", 5), ("银行账号", 5), ("账户名称", 4), ("转账", 3), ("付款", 2), ("回单", 4), ("汇款", 3)]
        case .explanation:
            return [("说明", 3), ("情况说明", 5), ("用途", 2), ("来源", 2), ("澄清", 4), ("审核", 2), ("关于", 1.5)]
        case .screenshot, .other:
            return []
        }
    }
}

enum DossierFieldKind: String, CaseIterable, Codable {
    case entityName, creditCode, legalRep, personName, idNumber, phone, email, address, appName, bankAccount, website, counterparty

    var title: String {
        switch self {
        case .entityName: return tr("主体名称", "Entity name")
        case .creditCode: return tr("统一社会信用代码", "Unified social credit code")
        case .legalRep: return tr("法定代表人", "Legal representative")
        case .personName: return tr("联系人 / 姓名", "Contact / name")
        case .idNumber: return tr("身份证号", "ID number")
        case .phone: return tr("手机号", "Mobile")
        case .email: return tr("邮箱", "Email")
        case .address: return tr("地址", "Address")
        case .appName: return tr("产品 / App 名称", "Product / App name")
        case .bankAccount: return tr("银行账号", "Bank account")
        case .website: return tr("网址", "Website")
        case .counterparty: return tr("合作方 / 乙方", "Counterparty")
        }
    }

    /// Compact label for the island card.
    var shortTitle: String {
        switch self {
        case .creditCode: return tr("信用代码", "Credit code")
        case .personName: return tr("联系人", "Contact")
        case .appName: return tr("App 名称", "App name")
        case .counterparty: return tr("合作方", "Counterparty")
        default: return title
        }
    }

    /// Fields where a mismatch across documents is worth a human look.
    var isIdentity: Bool {
        switch self {
        case .entityName, .creditCode, .legalRep, .idNumber, .appName, .bankAccount: return true
        default: return false
        }
    }

    /// Mask sensitive numbers on screen (the exported document keeps full values).
    func masked(_ value: String) -> String {
        switch self {
        case .idNumber, .bankAccount:
            guard value.count > 8 else { return value }
            return String(value.prefix(4)) + String(repeating: "•", count: max(0, value.count - 8)) + String(value.suffix(4))
        case .phone:
            guard value.count == 11 else { return value }
            return String(value.prefix(3)) + "••••" + String(value.suffix(4))
        default:
            return value
        }
    }
}

struct DossierHit: Hashable, Codable {
    let kind: DossierFieldKind
    let value: String
}

struct DossierFact: Hashable, Codable {
    let label: String
    let value: String
}

/// A sensitive region to black out (normalised rect, Vision coordinates: origin bottom-left).
struct DossierRedaction: Hashable, Codable {
    let page: Int
    let rect: CGRect
}

struct DossierDocument: Identifiable, Codable {
    let id: UUID
    let relativePath: String
    var fileSize: Int = 0
    var facts: [DossierFact] = []
    var redactions: [DossierRedaction] = []
    var name: String { (relativePath as NSString).lastPathComponent }
    var category: DossierCategory
    var text: String
    var pageCount: Int
    var usedOCR: Bool
    var hits: [DossierHit]
    var dates: [String]
    var amounts: [String]
    var error: String?

    /// First meaningful line(s), for the report.
    var gist: String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 }
        return lines.prefix(2).joined(separator: " / ")
    }
}

/// One field aggregated across all documents.
struct DossierField: Identifiable {
    struct Variant: Identifiable, Hashable {
        var id: String { value }
        let value: String
        var sources: [String]
    }

    var id: DossierFieldKind { kind }
    let kind: DossierFieldKind
    var variants: [Variant]
    /// Pairs that differ by one character (likely OCR misreads rather than real differences).
    var looksLikeOCRSlip: Bool
    var chosen: String?

    var needsConfirmation: Bool { variants.count > 1 && chosen == nil && kind.isIdentity }
    var resolvedValue: String? { chosen ?? (variants.count == 1 ? variants[0].value : nil) }
}

// MARK: - Submission checklist

enum DossierChecklistKind: String, CaseIterable, Codable {
    case app, game, none

    var title: String {
        switch self {
        case .app: return tr("App 上架", "App submission")
        case .game: return tr("游戏上架", "Game submission")
        case .none: return tr("不检查", "Off")
        }
    }
}

struct DossierChecklistItem: Identifiable {
    var id: String { title }
    let title: String
    var shortTitle: String {
        switch title {
        case "软件著作权证书": return "软著"
        case "ICP / App 备案": return "备案"
        case "防沉迷 / 实名认证": return "防沉迷"
        case "法人身份证": return "身份证"
        default: return title
        }
    }
    let required: Bool
    let satisfiedBy: [String]   // file names
    var present: Bool { !satisfiedBy.isEmpty }
}

// MARK: - History

struct DossierSnapshot: Codable {
    let date: Date
    let folder: String
    let files: [String: Int]          // relative path → size
    let fields: [String: String]      // field kind → resolved value
}

struct DossierDiff {
    let previousDate: Date
    let added: [String]
    let removed: [String]
    let modified: [String]
    let changedFields: [(DossierFieldKind, String, String)]   // kind, old, new

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty && changedFields.isEmpty }

    /// Very short form for the island chip: "+1 改1 变1".
    var shortSummary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("+\(added.count)") }
        if !removed.isEmpty { parts.append("−\(removed.count)") }
        if !modified.isEmpty { parts.append(tr("改\(modified.count)", "~\(modified.count)")) }
        if !changedFields.isEmpty { parts.append(tr("信息变\(changedFields.count)", "Δ\(changedFields.count)")) }
        return parts.isEmpty ? tr("无变化", "no changes") : parts.joined(separator: " ")
    }

    var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append(tr("新增 \(added.count)", "\(added.count) added")) }
        if !removed.isEmpty { parts.append(tr("删除 \(removed.count)", "\(removed.count) removed")) }
        if !modified.isEmpty { parts.append(tr("改动 \(modified.count)", "\(modified.count) modified")) }
        if !changedFields.isEmpty { parts.append(tr("信息变更 \(changedFields.count)", "\(changedFields.count) facts changed")) }
        return parts.isEmpty ? tr("与上一版相同", "Same as last version") : parts.joined(separator: " · ")
    }
}
