//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import AppKit
import Foundation
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]

    /// Apps whose full-screen windows are almost always video.
    static let videoApps: Set<String> = [
        "com.bytedance.douyin.desktop", "com.ss.iphone.ugc.Aweme", "tv.danmaku.bilibili", "com.bilibili.bilibiliPC",
        "com.iqiyi.player", "com.tencent.tenvideo", "com.youku.mac", "com.mgtv.mac",
        "com.colliderli.iina", "org.videolan.vlc", "io.mpv", "com.firecore.infuse", "com.movist.MovistPro",
        "com.apple.QuickTimePlayerX", "com.apple.TV", "com.netflix.Netflix", "com.amazon.aiv.AIVApp",
        "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.brave.Browser", "com.vivaldi.Vivaldi",
    ]
    static let videoAppPrefixes = ["com.google.Chrome.app.", "com.apple.Safari.WebApp", "org.chromium."]
    
    private var monitorTask: Task<Void, Never>?
    
    private var spaceStatus: [String: Bool] = [:]
    private var windowStatus: [String: Bool] = [:]
    private var pollTimer: Timer?

    private init() {
        startMonitoring()
        // MacroVisionKit's space monitor can miss full-screen spaces (e.g. on newer macOS or mirrored
        // displays), so also look at the windows themselves.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in FullscreenMediaDetector.shared.pollWindows() }
        }
    }

    /// A screen counts as full-screen when an app window exactly covers it.
    private func pollWindows() {
        // "Always show" never hides, so there's nothing to detect.
        guard Defaults[.hideNotchOption] != .never else {
            if !windowStatus.isEmpty { windowStatus = [:]; publish() }
            return
        }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        var status: [String: Bool] = [:]
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            // CG window bounds use a top-left origin on the main display.
            let f = screen.frame
            let target = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
            var bundles: [String] = []
            for w in list {
                guard (w[kCGWindowLayer as String] as? Int) == 0,
                      let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                      abs(x - target.minX) < 2, abs(y - target.minY) < 2,
                      abs(width - target.width) < 2, abs(height - target.height) < 2,
                      let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { continue }
                bundles.append(bundle)
            }
            status[uuid] = bundles.isEmpty ? false : shouldHide(forApps: bundles)
        }
        if status != windowStatus {
            windowStatus = status
            publish()
        }
    }

    private func shouldHide(forApps apps: [String]) -> Bool {
        guard Defaults[.hideNotchOption] == .nowPlayingOnly else { return true }
        let source = MusicManager.shared.bundleIdentifier
        return apps.contains { app in
            app == source || Self.videoApps.contains(app) || Self.videoAppPrefixes.contains { app.hasPrefix($0) }
        }
    }

    private func publish() {
        var merged = spaceStatus
        for (k, v) in windowStatus { merged[k] = (merged[k] ?? false) || v }
        if merged != fullscreenStatus { fullscreenStatus = merged }
    }
    
    deinit {
        monitorTask?.cancel()
    }
    
    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]
        
        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly {
                    // Many players (Douyin, Bilibili, browsers…) never report to Now Playing, so also
                    // treat a full-screen space running a known video app or browser as "watching video".
                    let source = MusicManager.shared.bundleIdentifier
                    shouldDetect = space.runningApps.contains { app in
                        app == source || Self.videoApps.contains(app) || Self.videoAppPrefixes.contains { app.hasPrefix($0) }
                    }
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }
        
        spaceStatus = newStatus
        publish()
    }
}

