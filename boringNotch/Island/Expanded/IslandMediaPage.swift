//
//  IslandMediaPage.swift
//  boringNotch – Dynamic Island skin
//
//  Now Playing card, laid out to the positions measured from Apple's MacBook Pro
//  island (278 × 148 pt):
//    artwork 50 pt @ (15, 15) r 10 · title/artist 13 pt @ x 74 · waveform top-right
//    scrubber row centred at y 81 (timestamps 10.5 pt, bar x 46…232)
//    transport centred at y 117: ⏪ x 66 · ⏯ x 139 · ⏩ x 212
//

import Defaults
import SwiftUI

@MainActor
struct IslandMediaPage: View {
    var namespace: Namespace.ID

    @ObservedObject private var music = MusicManager.shared

    private var tint: Color { Color.islandTint(music.avgColor) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Artwork
            Button { music.openMusicApp() } label: {
                IslandAlbumArt(image: music.albumArt, size: 50, radius: 10, dimmed: false)
                    .matchedGeometryEffect(id: "island.art", in: namespace)
                    .scaleEffect(music.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: music.isPlaying)
            }
            .buttonStyle(IslandPressStyle())
            .offset(x: 15, y: 15)

            // Title + artist
            VStack(alignment: .leading, spacing: -1) {
                Text(music.songTitle.isEmpty ? "未在播放" : music.songTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(music.artistName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .frame(width: 150, alignment: .leading)
            .offset(x: 74, y: 31)

            // Live waveform, tinted with the artwork colour
            IslandWaveform(color: tint, isPlaying: music.isPlaying, bars: 5, barWidth: 2, spacing: 1.6)
                .frame(width: 17, height: 12)
                .offset(x: 278 - 20 - 17, y: 33)

            // Scrubber row
            IslandScrubber(tint: tint)
                .frame(width: 278 - 32, height: 14)
                .offset(x: 16, y: 81 - 7)

            // Transport
            transport
                .frame(width: 278, height: 34)
                .offset(y: 117 - 17)
        }
        .frame(width: 278, height: 148, alignment: .topLeading)
    }

    private var transport: some View {
        ZStack {
            IslandTransportButton(symbol: "backward.fill", size: 19) { music.previousTrack() }
                .position(x: 66, y: 17)
            IslandTransportButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 27) { music.togglePlay() }
                .position(x: 139, y: 17)
            IslandTransportButton(symbol: "forward.fill", size: 19) { music.nextTrack() }
                .position(x: 212, y: 17)
        }
    }
}

/// Plain white transport glyph with a soft hover plate and springy press.
struct IslandTransportButton: View {
    var symbol: String
    var size: CGFloat
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: size + 18, height: size + 12)
                .background(
                    Capsule().fill(Color.white.opacity(hovering ? 0.1 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Apple-style scrubber: "2:35 ━━━━━━━━──── -1:31". Grows a little under the pointer.
@MainActor
struct IslandScrubber: View {
    var tint: Color

    @ObservedObject private var music = MusicManager.shared
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: music.isPlaying ? 1 / 30 : nil, paused: !music.isPlaying)) { ctx in
            let duration = max(music.songDuration, 0.01)
            let elapsed = dragValue.map { $0 * duration } ?? music.estimatedPlaybackPosition(at: ctx.date)
            let fraction = min(1, max(0, elapsed / duration))
            let active = hovering || dragValue != nil
            HStack(spacing: 4) {
                Text(elapsed.islandMediaTime)
                    .frame(width: 30, alignment: .leading)
                    .fixedSize()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white.opacity(active ? 0.95 : 0.6))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: active ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragValue = min(1, max(0, v.location.x / geo.size.width)) }
                            .onEnded { v in
                                music.seek(to: min(1, max(0, v.location.x / geo.size.width)) * duration)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dragValue = nil }
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: active)
                }
                .onHover { hovering = $0 }
                Text("-" + max(0, duration - elapsed).islandMediaTime)
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

extension TimeInterval {
    var islandMediaTime: String {
        guard self.isFinite else { return "0:00" }
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
