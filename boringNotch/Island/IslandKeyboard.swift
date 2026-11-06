//
//  IslandKeyboard.swift
//  boringNotch – Dynamic Island skin
//
//  Keyboard control: the global shortcut (default ⌘⇧I) opens the island with key focus.
//    ← / →      previous / next card
//    1 … 9      jump to card
//    Esc / ⌘⇧I  close and hand focus back to the app you were in
//

import AppKit
import Combine
import SwiftUI

@MainActor
enum IslandKeyboard {
    private static var monitor: Any?
    private static var previousApp: NSRunningApplication?
    private static var stateObserver: AnyCancellable?

    static func toggle(_ vm: BoringViewModel) {
        if vm.notchState == .open {
            close(vm)
        } else {
            open(vm)
        }
    }

    static func open(_ vm: BoringViewModel) {
        let me = NSRunningApplication.current
        if let front = NSWorkspace.shared.frontmostApplication, front != me { previousApp = front }

        withAnimation(IslandMotion.open) { vm.open() }
        IslandUIState.shared.keyboardFocus = true

        // Let the island take key focus just for this session.
        for window in NSApp.windows.compactMap({ $0 as? BoringNotchSkyLightWindow }) {
            window.allowsKeyFocus = true
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0 is BoringNotchSkyLightWindow && $0.isVisible }) {
            window.makeKey()
        }

        monitor.map(NSEvent.removeMonitor)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, vm: vm) ? nil : event
        }
        // Closing by any other means (mouse, swipe up, timeout) also ends keyboard mode.
        stateObserver = vm.$notchState.dropFirst().sink { state in
            if state == .closed { Task { @MainActor in endFocus() } }
        }
    }

    static func close(_ vm: BoringViewModel) {
        withAnimation(IslandMotion.close) { vm.close() }
        endFocus()
    }

    private static func endFocus() {
        guard IslandUIState.shared.keyboardFocus else { return }
        IslandUIState.shared.keyboardFocus = false
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        stateObserver = nil
        for window in NSApp.windows.compactMap({ $0 as? BoringNotchSkyLightWindow }) {
            window.allowsKeyFocus = false
            window.resignKey()
        }
        previousApp?.activate()
        previousApp = nil
    }

    /// Returns true when the key was consumed.
    private static func handle(_ event: NSEvent, vm: BoringViewModel) -> Bool {
        // Leave text fields (e.g. future search) alone for printable keys.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 123: // ←
            NotificationCenter.default.post(name: .islandStep, object: -1); return true
        case 124: // →
            NotificationCenter.default.post(name: .islandStep, object: 1); return true
        case 53: // Esc
            close(vm); return true
        default:
            break
        }
        if flags.isEmpty || flags == .numericPad, let chars = event.charactersIgnoringModifiers,
           let n = Int(chars), (1...9).contains(n) {
            NotificationCenter.default.post(name: .islandJump, object: n - 1)
            return true
        }
        return false
    }
}
