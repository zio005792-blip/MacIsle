//
//  IslandMetrics.swift
//  boringNotch – Dynamic Island skin
//
//  Geometry for the floating Mac-style Dynamic Island.
//
//  Proportions were measured from Apple's MacBook Pro (PROLED XDR) product imagery
//  (menu bar text used as the 13 pt reference):
//    • resting pill   ≈ 58 × 32 pt capsule (w/h ≈ 1.8), ≈ 0.73 × menu-bar height,
//                       top gap ≈ 0.18 × menu-bar height, camera ≈ 13 pt right of centre
//    • expanded music ≈ 277 × 147 pt, corner ≈ 30 pt, 15 pt insets, 50 pt artwork,
//                       13 pt title/artist, ~10.5 pt timestamps
//  The resting pill scales with the host menu bar; expanded cards use absolute points.
//

import AppKit
import SwiftUI

/// What the island is currently showing. Drives size, shape and content.
enum IslandPresentation: Equatable {
    case hidden
    case idle
    case compact(IslandActivity)
    case hud(IslandHUDKind)
    case alert(IslandAlert)
    case expanded(IslandTab)

    /// Stable identity used for content transitions (values like HUD level are excluded on purpose).
    var key: String {
        switch self {
        case .hidden: return "hidden"
        case .idle: return "idle"
        case .compact(let a): return "compact.\(a.rawValue)"
        case .hud(let k): return "hud.\(k.rawValue)"
        case .alert(let a): return "alert.\(a.key)"
        case .expanded: return "expanded"
        }
    }

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }
}

/// Long-running activities that can live in the compact island (and its bubble).
enum IslandActivity: String, CaseIterable, Equatable {
    case agent
    case dossier
    case timer
    case music
    case keepAwake
    case charging
}

enum IslandHUDKind: String, Equatable {
    case volume, brightness, backlight, mic
}

enum IslandAlert: Equatable {
    case power(plugged: Bool)
    case track
    case timerDone
    case copied(String)
    case agent
    case dossier

    var key: String {
        switch self {
        case .power(let p): return "power.\(p)"
        case .track: return "track"
        case .timerDone: return "timerDone"
        case .copied: return "copied"
        case .agent: return "agent"
        case .dossier: return "dossier"
        }
    }
}

@MainActor
struct IslandMetrics {
    /// The transparent host window. Large enough for the widest card plus its shadow.
    static let windowSize = CGSize(width: 520, height: 260)

    /// Apple's expanded corner radius (continuous).
    static let expandedRadius: CGFloat = 30

    let menuBarHeight: CGFloat
    let hasHardwareNotch: Bool
    let hardwareNotchWidth: CGFloat

    init(screenUUID: String?) {
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        if let screen {
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            // When the menu bar auto-hides visibleFrame reaches the top; fall back to the system thickness.
            menuBarHeight = bar > 8 ? bar : max(NSStatusBar.system.thickness, 24)
            hasHardwareNotch = screen.safeAreaInsets.top > 0
            if let l = screen.auxiliaryTopLeftArea?.width, let r = screen.auxiliaryTopRightArea?.width {
                hardwareNotchWidth = screen.frame.width - l - r
            } else {
                hardwareNotchWidth = 0
            }
        } else {
            menuBarHeight = 30
            hasHardwareNotch = false
            hardwareNotchWidth = 0
        }
    }

    // MARK: Resting pill

    /// Height of the resting pill: 0.73 × menu bar, like the MacBook Pro island.
    var compactHeight: CGFloat {
        if hasHardwareNotch { return max(menuBarHeight, 30) }
        return min(32, max(20, (menuBarHeight * 0.73).rounded()))
    }

    /// Gap between the top of the screen and the island.
    var topGap: CGFloat {
        if hasHardwareNotch { return 0 }
        return min(8, max(2, (menuBarHeight * 0.18).rounded()))
    }

    var idleWidth: CGFloat {
        if hasHardwareNotch, hardwareNotchWidth > 0 { return hardwareNotchWidth }
        return (compactHeight * 1.81).rounded()
    }

    /// Where the (virtual) camera sits, relative to the island centre.
    var cameraOffset: CGFloat { (compactHeight * 13 / 32).rounded() }
    var cameraDiameter: CGFloat { max(5, (compactHeight * 7.5 / 32).rounded()) }

    /// Width of one compact "ear" (leading / trailing slot) for an activity.
    func sideWidth(for activity: IslandActivity) -> CGFloat {
        let h = compactHeight
        switch activity {
        case .agent: return h + 28
        case .dossier: return h + 30
        case .music: return h + 8
        case .timer: return h + 26
        case .keepAwake: return h + 2
        case .charging: return h + 20
        }
    }

    // MARK: Sizes

    func size(for presentation: IslandPresentation) -> CGSize {
        let h = compactHeight
        switch presentation {
        case .hidden:
            return CGSize(width: idleWidth * 0.6, height: h * 0.6)
        case .idle:
            return CGSize(width: idleWidth, height: h)
        case .compact(let a):
            return CGSize(width: idleWidth + 2 * sideWidth(for: a), height: h)
        case .hud:
            return CGSize(width: idleWidth + 2 * (h + 46), height: h)
        case .alert(let alert):
            switch alert {
            case .power: return CGSize(width: idleWidth + 2 * (h + 58), height: h)
            case .copied: return CGSize(width: idleWidth + 2 * (h + 70), height: h)
            case .track: return CGSize(width: 270, height: 62)
            case .timerDone: return CGSize(width: 270, height: 62)
            case .agent: return CGSize(width: 300, height: 62)
            case .dossier: return CGSize(width: 300, height: 62)
            }
        case .expanded(let tab):
            return Self.cardSize(for: tab)
        }
    }

    /// Expanded card sizes. `.media` is Apple's exact Now Playing card.
    static func cardSize(for tab: IslandTab) -> CGSize {
        switch tab {
        case .media: return CGSize(width: 278, height: 148)
        case .agents: return CGSize(width: 352, height: 148)
        case .screens: return CGSize(width: 352, height: 148)
        case .dossier: return CGSize(width: 400, height: 176)
        case .home: return CGSize(width: 352, height: 148)
        case .timer: return CGSize(width: 300, height: 148)
        case .calendar: return CGSize(width: 352, height: 176)
        case .system: return CGSize(width: 352, height: 148)
        case .clipboard: return CGSize(width: 400, height: 152)
        case .shelf: return CGSize(width: 400, height: 168)
        }
    }

    func cornerRadius(for presentation: IslandPresentation, size: CGSize) -> CGFloat {
        switch presentation {
        case .expanded: return Self.expandedRadius
        case .alert(.track), .alert(.timerDone), .alert(.agent), .alert(.dossier): return 24
        default: return size.height / 2
        }
    }

    /// Diameter of the detached "minimal" bubble used for a second activity.
    var bubbleDiameter: CGFloat { compactHeight }
    var bubbleGap: CGFloat { max(4, (compactHeight * 0.25).rounded()) }
}

// MARK: - Motion

enum IslandMotion {
    /// Opening: a lively spring with a touch of overshoot, like the iPhone island.
    static let open = Animation.spring(response: 0.48, dampingFraction: 0.76, blendDuration: 0)
    /// Closing: quick and settled, no wobble.
    static let close = Animation.spring(response: 0.38, dampingFraction: 0.92, blendDuration: 0)
    /// Changes between compact states.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    /// Switching cards while expanded.
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.84, blendDuration: 0)
    /// Hover / press feedback.
    static let touch = Animation.spring(response: 0.28, dampingFraction: 0.62, blendDuration: 0)
    /// Content fade-in, slightly delayed so the shape leads and the content follows.
    static let contentIn = Animation.spring(response: 0.4, dampingFraction: 0.86).delay(0.07)
    static let contentOut = Animation.easeOut(duration: 0.12)
}
