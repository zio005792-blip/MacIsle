//
//  KeepAwakeManager.swift
//  MacIsle
//
//  "Caffeinate" from the island: prevents display + idle sleep, optionally for a set time.
//

import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    @Published private(set) var isActive = false
    @Published private(set) var until: Date?

    private var assertionID: IOPMAssertionID = 0
    private var expiry: AnyCancellable?

    func toggle() {
        isActive ? stop() : start(for: nil)
    }

    /// - Parameter duration: nil = indefinitely.
    func start(for duration: TimeInterval?) {
        stop()
        let reason = "MacIsle keep-awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        guard result == kIOReturnSuccess else { return }
        isActive = true
        if let duration {
            let end = Date.now.addingTimeInterval(duration)
            until = end
            expiry = Timer.publish(every: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] now in
                    Task { @MainActor in
                        if now >= end { self?.stop() }
                    }
                }
        } else {
            until = nil
        }
    }

    func stop() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        expiry = nil
        until = nil
        isActive = false
    }
}
