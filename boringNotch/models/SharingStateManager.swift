//
//  SharingStateManager.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-10.
//

import AppKit
import Combine
import Foundation

extension Notification.Name {
	static let sharingDidFinish = Notification.Name("com.boringNotch.sharingDidFinish")
}

@MainActor
final class SharingStateManager: ObservableObject {
	static let shared = SharingStateManager()

	private var activeSessions: Int = 0 {
		didSet {
			let newValue = activeSessions > 0
			if newValue != preventNotchClose {
				preventNotchClose = newValue
				if !newValue {
					NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
				}
			}
		}
	}

	@Published var preventNotchClose: Bool = false

	private var activeDelegates: [UUID: SharingLifecycleDelegate] = [:]

	private init() {}
	
	func requestCloseIfReady() {
		if !preventNotchClose {
			NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
		}
	}

	func beginInteraction() {
		activeSessions += 1
	}

	func endInteraction() {
		if activeSessions > 0 { activeSessions -= 1 }
	}

	func makeDelegate(onEnd: (() -> Void)? = nil) -> SharingLifecycleDelegate {
		let id = UUID()
		let delegate = SharingLifecycleDelegate(id: id, onEnd: { [weak self] in
			onEnd?()
			self?.unregisterDelegate(id: id)
		}, onBegin: { [weak self] in
			self?.beginInteraction()
		}, onFinish: { [weak self] in
			self?.endInteraction()
		})
		activeDelegates[id] = delegate
		return delegate
	}

	private func unregisterDelegate(id: UUID) {
		activeDelegates.removeValue(forKey: id)
	}
}

final class SharingLifecycleDelegate: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
	let id: UUID
	private let onEnd: () -> Void
	private let onBegin: () -> Void
	private let onFinish: () -> Void

	private var pickerActive = false
	private var serviceInProgress = false
	private var finished = false
	private var timeoutTask: Task<Void, Never>?

	init(id: UUID, onEnd: @escaping () -> Void, onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
		self.id = id
		self.onEnd = onEnd
		self.onBegin = onBegin
		self.onFinish = onFinish
	}
	
	deinit {
		timeoutTask?.cancel()
	}

	func markPickerBegan() {
		guard !pickerActive else { return }
		pickerActive = true
		onBegin()
	}

	func markServiceBegan() {
		guard !serviceInProgress else { return }
		serviceInProgress = true
		onBegin()
		startTimeoutFallback()
	}
	
	private func startTimeoutFallback() {
		timeoutTask?.cancel()
		timeoutTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard let self = self, !Task.isCancelled else { return }
			if !self.finished {
				self.finishIfNeeded()
			}
		}
	}

	private func finishIfNeeded() {
		guard !finished else { return }
		finished = true
		Task { @MainActor in ShareAnchorWindow.dismiss() }
		timeoutTask?.cancel()
		onFinish()
		onEnd()
	}

	// MARK: - NSSharingServicePickerDelegate

	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		if service == nil {
			if pickerActive && !serviceInProgress {
				finishIfNeeded()
			}
			return
		}

		service?.delegate = self
		serviceInProgress = true
		MainActor.assumeIsolated { _ = ShareAnchorWindow.prepare() }
		startTimeoutFallback()
	}

	// MARK: - NSSharingServiceDelegate

	func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
		if !pickerActive && !serviceInProgress {
			onBegin()
		}
		serviceInProgress = true
	}

	func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
		finishIfNeeded()
	}

	/// Share extensions (Messages, Notes, Mail…) attach their compose UI to a *key-capable*
	/// source window. The island panel can never become key, which made ShareKit assert and
	/// abort the whole app. Hand it a transparent anchor window instead.
	func sharingService(_ sharingService: NSSharingService,
	                    sourceWindowForShareItems items: [Any],
	                    sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
		MainActor.assumeIsolated { ShareAnchorWindow.prepare() }
	}

	func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
		MainActor.assumeIsolated { ShareAnchorWindow.anchorRect }
	}

	func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
		finishIfNeeded()
	}
}



/// Invisible, key-capable window just under the island, used as the anchor for share sheets.
@MainActor
final class ShareAnchorWindow: NSPanel {
	private static var shared: ShareAnchorWindow?

	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }

	static var anchorRect: NSRect {
		let screen = NSScreen.main ?? NSScreen.screens.first
		let frame = screen?.frame ?? .zero
		let visible = screen?.visibleFrame ?? .zero
		return NSRect(x: frame.midX - 1, y: visible.maxY - 2, width: 2, height: 2)
	}

	@discardableResult
	static func prepare() -> NSWindow {
		let window = shared ?? {
			let w = ShareAnchorWindow(contentRect: anchorRect, styleMask: [.borderless, .nonactivatingPanel],
			                          backing: .buffered, defer: false)
			w.isOpaque = false
			w.backgroundColor = .clear
			w.hasShadow = false
			w.level = .floating
			w.isReleasedWhenClosed = false
			w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
			shared = w
			return w
		}()
		window.setFrame(anchorRect, display: false)
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		return window
	}

	static func dismiss() {
		shared?.orderOut(nil)
	}
}
