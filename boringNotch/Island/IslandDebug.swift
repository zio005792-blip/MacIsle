//
//  IslandDebug.swift
//  boringNotch – Dynamic Island skin
//
//  DEBUG-only remote control used for visual testing:
//  echo open > ~/Library/Containers/theboringteam.boringnotch/Data/tmp/island-debug.txt
//  commands: open | close | tab:<name> | timer[:sec] | pomodoro | awake | alert:<kind> | hud:<level>
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum IslandDebug {
    /// Commands are read from `<container>/tmp/island-debug.txt` (sandbox-friendly), one per write.
    static let commandURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("island-debug.txt")
    private static var timer: Timer?
    static var synthActive = false
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("island-log.txt")

    nonisolated static func log(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    static func install(vm: BoringViewModel) {
        guard timer == nil else { return }
        NSLog("[Island] debug channel at %@", commandURL.path)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                guard let text = try? String(contentsOf: commandURL, encoding: .utf8) else { return }
                try? FileManager.default.removeItem(at: commandURL)
                for line in text.split(separator: "\n") {
                    handle(line.trimmingCharacters(in: .whitespaces), vm: vm)
                }
            }
        }
    }

    private static func synthSwipe(total: Double, steps: Int, noise: Double) {
        log("synth request total=\(total) windows=\(NSApp.windows.map { String(describing: type(of: $0)) })")
        guard let window = NSApp.windows.first(where: { $0 is BoringNotchSkyLightWindow }) else { return }
        let center = CGPoint(x: window.frame.midX, y: NSScreen.screens[0].frame.maxY - (window.frame.maxY - 60))
        func make(_ dx: Double, _ dy: Double, _ phase: Int64) -> NSEvent? {
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
            e.location = center
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
            return NSEvent(cgEvent: e)
        }
        synthActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { synthActive = false }
        var events: [NSEvent?] = [make(0, 0, 128)]
        for i in 0..<steps { events.append(make(total / Double(steps), noise * (i % 2 == 0 ? 1 : -0.6), i == 0 ? 1 : 2)) }
        events.append(make(0, 0, 4))
        for (i, e) in events.enumerated() {
            guard let e else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.008) {
                log("synth window=\(String(describing: e.window.map { type(of: $0) })) phase=\(e.phase.rawValue) dx=\(e.scrollingDeltaX) precise=\(e.hasPreciseScrollingDeltas)")
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    private static func handle(_ action: String, vm: BoringViewModel) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        NSLog("[Island] debug action %@", action)
        switch parts.first ?? "" {
        case "screens":
            // Converts every image in <container>/tmp/screens-in
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screens-in")
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            StoreScreenshots.shared.process(files)
        case "show":
            vm.hideOnClosed = false
        case "dossier":
            DossierCenter.shared.start(folder: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(arg.isEmpty ? "dossier-sample" : arg))
        case "dossier-export":
            DossierCenter.shared.export()
        case "dossier-majority":
            DossierCenter.shared.acceptMajorityForAll()
        case "swipe":
            // swipe:<totalDX>:<steps>:<dyNoise> – synthetic phased trackpad scroll through the real event path
            let f = arg.split(separator: ":").compactMap { Double($0) }
            synthSwipe(total: f.first ?? -60, steps: Int(f.count > 1 ? f[1] : 10), noise: f.count > 2 ? f[2] : 0)
        case "open":
            withAnimation(IslandMotion.open) { vm.open() }
        case "close":
            withAnimation(IslandMotion.close) { vm.close() }
        case "tab":
            if let tab = IslandTab(rawValue: arg) { IslandUIState.shared.tab = tab }
        case "timer":
            if IslandTimer.shared.isActive { IslandTimer.shared.cancel() } else { IslandTimer.shared.start(seconds: Double(arg) ?? 300) }
        case "pomodoro":
            IslandTimer.shared.startPomodoro()
        case "awake":
            KeepAwakeManager.shared.toggle()
        case "alert":
            switch arg {
            case "power": IslandUIState.shared.flash(.power(plugged: true), duration: 4)
            case "track": IslandUIState.shared.flash(.track, duration: 4)
            case "done": IslandUIState.shared.flash(.timerDone, duration: 4)
            default: IslandUIState.shared.flash(.copied("Hello, Island"), duration: 4)
            }
        case "hud":
            BoringViewCoordinator.shared.sneakPeek = sneakPeek(show: true, type: .volume, value: CGFloat(Double(arg) ?? 0.6), icon: "")
        default:
            break
        }
    }
}
#endif
