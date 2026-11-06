//
//  IslandSettings.swift
//  boringNotch – Dynamic Island skin
//
//  User preferences for the island (shown in Settings › 灵动岛).
//

import Combine
import Defaults
import SwiftUI

@MainActor
final class IslandSettings: ObservableObject {
    static let shared = IslandSettings()

    /// Swipe distance (pt) that pages on release.
    @AppStorage("island.swipe.commit") var swipeCommit: Double = 30
    /// Minimum travel (pt) for a fast flick to page.
    @AppStorage("island.swipe.flick") var swipeFlick: Double = 14
    /// Resting pill size multiplier.
    @AppStorage("island.scale") var scale: Double = 1.0
    /// Pick the card automatically when opening.
    @AppStorage("island.predict") var predict: Bool = true
    /// Show the "猜你想用 · reason" chip.
    @AppStorage("island.predict.hint") var predictHint: Bool = true
    @AppStorage("island.tabs.hidden") private var hiddenRaw: String = ""
    @AppStorage("island.tabs.order") private var orderRaw: String = ""

    var hiddenTabs: Set<IslandTab> {
        Set(hiddenRaw.split(separator: ",").compactMap { IslandTab(rawValue: String($0)) })
    }

    func setHidden(_ tab: IslandTab, _ hidden: Bool) {
        var s = hiddenTabs
        if hidden { s.insert(tab) } else { s.remove(tab) }
        hiddenRaw = s.map(\.rawValue).sorted().joined(separator: ",")
        objectWillChange.send()
    }

    /// Card order chosen by the user; new cards are appended in their default position.
    var order: [IslandTab] {
        let saved = orderRaw.split(separator: ",").compactMap { IslandTab(rawValue: String($0)) }
        let missing = IslandTab.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    func move(from source: IndexSet, to destination: Int) {
        var list = order
        list.move(fromOffsets: source, toOffset: destination)
        orderRaw = list.map(\.rawValue).joined(separator: ",")
        objectWillChange.send()
    }

    func resetOrder() {
        orderRaw = ""
        hiddenRaw = ""
        objectWillChange.send()
    }
}
