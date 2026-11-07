//
//  HUDAccess.swift
//  MacIsle
//
//  Turning on the volume / brightness HUD needs Accessibility. Instead of failing after a
//  0.5 s check (the switch used to flip itself off), wait for the user: open the right
//  System Settings pane and enable the feature the moment access is granted.
//

import AppKit
import Combine
import Defaults

@MainActor
final class HUDAccess: ObservableObject {
    static let shared = HUDAccess()

    enum State: Equatable { case idle, waiting, denied }

    @Published private(set) var state: State = .idle
    private var poll: Task<Void, Never>?

    var isOn: Bool { Defaults[.hudReplacement] || state == .waiting }

    func setEnabled(_ enabled: Bool) {
        poll?.cancel()
        guard enabled else {
            state = .idle
            Defaults[.hudReplacement] = false
            return
        }
        state = .waiting
        objectWillChange.send()
        poll = Task {
            if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                finish(granted: true)
                return
            }
            // Shows the system prompt, then the exact Settings pane.
            _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            Self.openSettings()
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                    finish(granted: true)
                    return
                }
            }
            finish(granted: false)
        }
    }

    private func finish(granted: Bool) {
        state = granted ? .idle : .denied
        if granted {
            Defaults[.hudReplacement] = true   // BoringViewCoordinator starts the key interceptor
            NSSound(named: "Tink")?.play()
        }
        objectWillChange.send()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
