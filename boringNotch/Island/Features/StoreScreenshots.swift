//
//  StoreScreenshots.swift
//  MacIsle
//
//  Drop screenshots on the island → exact App Store Connect sizes (opaque PNG, no alpha,
//  aspect-fill + centre crop, orientation preserved). Output: ~/Downloads/App Store 截图/<device>/
//

import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct StoreDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let portrait: CGSize

    static let all: [StoreDevice] = [
        StoreDevice(id: "iphone69", name: "iPhone 6.9 英寸", short: "6.9″", portrait: CGSize(width: 1320, height: 2868)),
        StoreDevice(id: "iphone65", name: "iPhone 6.5 英寸", short: "6.5″", portrait: CGSize(width: 1284, height: 2778)),
        StoreDevice(id: "iphone63", name: "iPhone 6.3 英寸", short: "6.3″", portrait: CGSize(width: 1206, height: 2622)),
        StoreDevice(id: "iphone55", name: "iPhone 5.5 英寸", short: "5.5″", portrait: CGSize(width: 1242, height: 2208)),
        StoreDevice(id: "ipad13", name: "iPad 13 英寸", short: "iPad 13″", portrait: CGSize(width: 2064, height: 2752)),
        StoreDevice(id: "ipad129", name: "iPad 12.9 英寸", short: "iPad 12.9″", portrait: CGSize(width: 2048, height: 2732)),
    ]
}

@MainActor
final class StoreScreenshots: ObservableObject {
    static let shared = StoreScreenshots()

    @AppStorage("island.store.devices") private var selectedRaw: String = "iphone69,iphone65,ipad13"
    @Published private(set) var isWorking = false
    @Published private(set) var lastResult: String?
    @Published private(set) var lastOutputFolder: URL?

    var selected: Set<String> {
        get { Set(selectedRaw.split(separator: ",").map(String.init)) }
        set { selectedRaw = newValue.sorted().joined(separator: ","); objectWillChange.send() }
    }

    func toggle(_ device: StoreDevice) {
        var s = selected
        if s.contains(device.id) { if s.count > 1 { s.remove(device.id) } } else { s.insert(device.id) }
        selected = s
    }

    /// Lets the user pick files when dragging is inconvenient.
    func pickFiles() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.message = "选择要转换成 App Store 尺寸的截图"
        let response = panel.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .OK { process(panel.urls) }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for p in fileProviders {
                if let url = await Self.loadURL(p) { urls.append(url) }
            }
            process(urls)
        }
        return true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }

    func process(_ urls: [URL]) {
        let images = urls.filter { ["png", "jpg", "jpeg", "heic", "tiff", "tif"].contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else {
            lastResult = "没有可用的图片"
            return
        }
        let devices = StoreDevice.all.filter { selected.contains($0.id) }
        isWorking = true
        lastResult = nil

        Task.detached(priority: .userInitiated) {
            let downloads = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")).resolvingSymlinksInPath()
            let root = downloads.appendingPathComponent("App Store 截图", isDirectory: true)
            var written = 0
            var failures = 0
            for device in devices {
                let folder = root.appendingPathComponent(device.short.replacingOccurrences(of: "″", with: "in"), isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for url in images {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let out = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
                    if Self.render(url, device: device, to: out) { written += 1 } else { failures += 1 }
                }
            }
            await MainActor.run {
                self.isWorking = false
                self.lastOutputFolder = root
                self.lastResult = failures == 0
                    ? "已生成 \(written) 张 · \(devices.count) 种尺寸"
                    : "已生成 \(written) 张，\(failures) 张失败"
                IslandUIState.shared.flash(.copied("截图已导出到下载"), duration: 2)
                if written > 0 { NSWorkspace.shared.activateFileViewerSelecting([root]) }
            }
        }
    }

    /// Aspect-fill into the exact target size on an opaque canvas.
    nonisolated private static func render(_ url: URL, device: StoreDevice, to out: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return false }

        let landscape = image.width > image.height
        let target = landscape ? CGSize(width: device.portrait.height, height: device.portrait.width) : device.portrait
        let w = Int(target.width), h = Int(target.height)

        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let scale = max(target.width / CGFloat(image.width), target.height / CGFloat(image.height))
        let dw = CGFloat(image.width) * scale, dh = CGFloat(image.height) * scale
        ctx.draw(image, in: CGRect(x: (target.width - dw) / 2, y: (target.height - dh) / 2, width: dw, height: dh))

        guard let result = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, result, nil)
        return CGImageDestinationFinalize(dest)
    }
}
