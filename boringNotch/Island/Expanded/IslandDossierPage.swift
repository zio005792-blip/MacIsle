//
//  IslandDossierPage.swift
//  MacIsle
//
//  资料整理 card: drop a client folder → live OCR progress → confirm conflicts → Word document.
//

import SwiftUI

@MainActor
struct IslandDossierPage: View {
    @ObservedObject private var center = DossierCenter.shared
    @State private var targeted = false

    var body: some View {
        Group {
            switch center.phase {
            case .idle, .failed:
                intake
            case .scanning(let done, let total, let current):
                scanning(done: done, total: total, current: current)
            case .review, .exporting:
                review
            case .finished(let url):
                finished(url)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: center.phase)
    }

    // MARK: Intake

    private var intake: some View {
        HStack(spacing: 14) {
            Button { center.pickFolder() } label: {
                VStack(spacing: 6) {
                    Image(systemName: targeted ? "folder.fill.badge.plus" : "folder.badge.questionmark")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.75))
                        .symbolEffect(.bounce, value: targeted)
                    Text(targeted ? tr("松手开始整理", "Release to start") : tr("拖入客户资料文件夹", "Drop a client folder"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(tr("或点击选择", "or click to choose"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: 150)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.22))
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(targeted ? 0.1 : 0.04)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(IslandPressStyle())
            .onDrop(of: [.fileURL], isTargeted: $targeted) { center.handleDrop($0) }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("资料整理", "Client Dossier"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                bullet("doc.viewfinder", tr("OCR 识别图片、扫描件、PDF、Word", "OCR: images, scans, PDF, Word"))
                bullet("square.grid.2x2", tr("自动分类：执照、证件、合同、发票…", "Sorts licences, IDs, contracts…"))
                bullet("checkmark.shield", tr("跨文件比对，标出不一致的信息", "Flags mismatches across files"))
                bullet("doc.richtext", tr("生成 Word 整理文档到「下载」", "Word report in Downloads"))
                Spacer(minLength: 0)
                if case .failed(let msg) = center.phase {
                    Text(msg).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.red.opacity(0.9)).lineLimit(1)
                } else {
                    Text(tr("全程在本机处理，资料不会上传", "Processed on this Mac — nothing is uploaded"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: Scanning

    private func scanning(done: Int, total: Int, current: String) -> some View {
        HStack(spacing: 18) {
            ZStack {
                IslandRing(progress: total > 0 ? Double(done) / Double(total) : 0.02, tint: .accentColor, lineWidth: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: done)
                VStack(spacing: 0) {
                    Text(total > 0 ? "\(done)/\(total)" : "…")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(tr("识别中", "Reading"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(center.folderName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .islandBreathing()
                    Text(current)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .id(current)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text(tr("可以先收起灵动岛去忙别的，识别完会提醒你", "Close the island anytime — you'll be notified"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
                Button(tr("取消", "Cancel")) { center.reset() }
                    .buttonStyle(IslandPillButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(center.folderName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(tr("\(center.documents.count) 份", "\(center.documents.count) files"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(center.categoryCounts, id: \.0) { c, n in
                            HStack(spacing: 3) {
                                Image(systemName: c.symbol).font(.system(size: 8.5, weight: .bold))
                                Text("\(c.title) \(n)").font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                }
                .frame(maxWidth: 210)
            }

            statusRow

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(center.fields
                        .filter { $0.kind.isIdentity || $0.variants.count == 1 }
                        .sorted { ($0.needsConfirmation ? 0 : 1) < ($1.needsConfirmation ? 0 : 1) }) { field in
                        fieldRow(field)
                    }
                }
            }

            HStack(spacing: 8) {
                let pending = center.pendingConfirmations.count
                Image(systemName: pending == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pending == 0 ? Color.green : Color.orange)
                Text(pending == 0 ? tr("已核对", "Verified") : tr("\(pending) 项待确认", "\(pending) to confirm"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if pending > 0 {
                    Button(tr("按多数", "Use Majority")) { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { center.acceptMajorityForAll() } }
                        .buttonStyle(IslandPillButtonStyle())
                }
                Button(tr("打码版", "Redacted")) { center.exportRedacted() }
                    .buttonStyle(IslandPillButtonStyle())
                    .help(tr("生成隐藏身份证号、银行卡号、手机号的报告，并给图片和 PDF 打码", "Creates a report with ID, card and phone numbers hidden, and redacts the images and PDFs"))
                Button {
                    center.export()
                } label: {
                    if center.phase == .exporting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label(tr("生成文档", "Create Report"), systemImage: "doc.richtext")
                    }
                }
                .buttonStyle(IslandPillButtonStyle(tint: .accentColor))
            }
        }
    }

    /// Submission checklist + comparison with the previous version of this client.
    private var statusRow: some View {
        HStack(spacing: 6) {
            Button {
                let all = DossierChecklistKind.allCases
                let i = all.firstIndex(of: center.checklistKind) ?? 0
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { center.checklistKind = all[(i + 1) % all.count] }
            } label: {
                let missing = center.missingRequired
                HStack(spacing: 4) {
                    Image(systemName: center.checklistKind == .none ? "list.bullet.clipboard" : (missing.isEmpty ? "checkmark.circle.fill" : "xmark.circle.fill"))
                        .foregroundStyle(center.checklistKind == .none ? Color.white.opacity(0.5) : (missing.isEmpty ? Color.green : Color.red))
                    Text(center.checklistKind == .none ? tr("不检查材料", "Checklist off")
                         : missing.isEmpty ? tr("\(center.checklistKind.title)材料齐全", "\(center.checklistKind.title): all materials present")
                         : tr("缺", "Missing: ") + missing.map { L($0.shortTitle) }.joined(separator: tr("、", ", ")))
                        .lineLimit(1)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .contentShape(Capsule())
            }
            .buttonStyle(IslandPressStyle())
            .help(tr("点击切换：App 上架 / 游戏上架 / 不检查\n", "Click to switch: App / Game submission / Off\n") + center.checklist.map { "\($0.present ? "✓" : ($0.required ? "✗" : "·")) \(L($0.title))" }.joined(separator: "\n"))

            if let diff = center.diff {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(tr("较上版 \(diff.shortSummary)", "vs last \(diff.shortSummary)")).lineLimit(1)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(diff.changedFields.isEmpty ? Color.white.opacity(0.6) : Color.orange)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .help(diffHelp(diff))
            }
            Spacer(minLength: 0)
        }
    }

    private func diffHelp(_ d: DossierDiff) -> String {
        var lines: [String] = []
        if !d.added.isEmpty { lines.append(tr("新增：", "Added: ") + d.added.joined(separator: "、")) }
        if !d.removed.isEmpty { lines.append(tr("删除：", "Removed: ") + d.removed.joined(separator: "、")) }
        if !d.modified.isEmpty { lines.append(tr("改动：", "Modified: ") + d.modified.joined(separator: "、")) }
        for (k, o, n) in d.changedFields { lines.append("\(k.title)：\(k.masked(o)) → \(k.masked(n))") }
        return lines.isEmpty ? tr("与上一版相同", "Same as last version") : lines.joined(separator: "\n")
    }

    private func fieldRow(_ field: DossierField) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(field.kind.shortTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 58, alignment: .leading)
            if field.variants.count == 1 {
                Text(field.kind.masked(field.variants[0].value))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(field.variants[0].sources.count > 1 ? tr("\(field.variants[0].sources.count) 份一致", "\(field.variants[0].sources.count) agree") : tr("1 份", "1 file"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(field.variants[0].sources.count > 1 ? Color.green.opacity(0.85) : .white.opacity(0.3))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(field.variants) { v in
                            let selected = field.chosen == v.value
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { center.choose(v.value, for: field.kind) }
                            } label: {
                                HStack(spacing: 3) {
                                    if selected { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                                    Text(field.kind.masked(v.value)).lineLimit(1)
                                    Text("×\(v.sources.count)").foregroundStyle(.white.opacity(0.4))
                                }
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(selected ? Color.black : .white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .frame(height: 19)
                                .background(Capsule().fill(selected ? Color.green : Color.orange.opacity(0.18)))
                            }
                            .buttonStyle(IslandPressStyle())
                            .help(v.sources.joined(separator: "\n"))
                        }
                    }
                }
                if field.looksLikeOCRSlip {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help(tr("两种写法只差一个字符，可能是识别误差，建议对照原件", "The two spellings differ by one character — possibly an OCR slip; check the original"))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(field.needsConfirmation ? Color.orange.opacity(0.08) : Color.white.opacity(0.04)))
    }

    // MARK: Finished

    private func finished(_ url: URL) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.green.opacity(0.18))
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: url)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("整理文档已生成", "Report created"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(center.redactedFolder == nil ? tr("下载 › 客户资料整理", "Downloads › Client Dossiers") : tr("打码版报告 + 打码后的图片 / PDF · 下载 › 客户资料整理", "Redacted report + redacted images / PDFs · Downloads › Client Dossiers"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(tr("打开", "Open")) { center.openResult() }.buttonStyle(IslandPillButtonStyle(tint: .accentColor))
                    Button(tr("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(IslandPillButtonStyle())
                    Button(tr("再整理一个", "Another Folder")) { center.reset() }.buttonStyle(IslandPillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}
