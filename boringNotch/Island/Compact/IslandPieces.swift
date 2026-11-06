//
//  IslandPieces.swift
//  boringNotch – Dynamic Island skin
//
//  Small reusable building blocks: waveform, rings, album art, transitions.
//

import SwiftUI

// MARK: - Waveform

/// Live-activity style equaliser bars. Pure function of time, so it stays perfectly
/// smooth at any refresh rate (165 Hz included) and costs nothing when paused.
struct IslandWaveform: View {
    var color: Color
    var isPlaying: Bool
    var bars: Int = 4
    var barWidth: CGFloat = 2.6
    var spacing: CGFloat = 2.2

    @State private var level: CGFloat = 0

    private static let speeds: [Double] = [5.3, 7.1, 6.2, 8.4, 5.9, 7.7]
    private static let phases: [Double] = [0.0, 1.7, 3.1, 0.9, 2.4, 4.0]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying && level == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let total = CGFloat(bars) * barWidth + CGFloat(bars - 1) * spacing
                var x = (size.width - total) / 2
                for i in 0..<bars {
                    let s = Self.speeds[i % Self.speeds.count]
                    let p = Self.phases[i % Self.phases.count]
                    // Two detuned sines give an organic, non-repeating motion.
                    let wave = 0.55 + 0.30 * sin(t * s + p) + 0.15 * sin(t * s * 1.73 + p * 2)
                    let amp = max(0.18, min(1, CGFloat(wave))) * level + 0.18 * (1 - level)
                    let h = max(barWidth, size.height * amp)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                    x += barWidth + spacing
                }
            }
        }
        .onAppear { level = isPlaying ? 1 : 0 }
        .onChange(of: isPlaying) { _, playing in
            withAnimation(.easeInOut(duration: 0.35)) { level = playing ? 1 : 0 }
        }
    }
}

// MARK: - Rings

struct IslandRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Album art

struct IslandAlbumArt: View {
    var image: NSImage
    var size: CGFloat
    var radius: CGFloat
    var dimmed: Bool = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .saturation(dimmed ? 0.4 : 1)
            .opacity(dimmed ? 0.65 : 1)
    }
}

// MARK: - Compact layout

/// Leading content | camera gap | trailing content, matching the island's "ears".
struct IslandCompactLayout<Leading: View, Trailing: View>: View {
    var size: CGSize
    var sideWidth: CGFloat
    var inset: CGFloat = 0
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: sideWidth - inset, height: size.height, alignment: .center)
            Spacer(minLength: 0)
            trailing
                .frame(width: sideWidth - inset, height: size.height, alignment: .center)
        }
        .padding(.horizontal, inset / 2 + max(3, size.height * 0.14))
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Transitions

/// Content blurs + scales in as the shape grows, and fades out fast when it shrinks.
struct IslandBlurModifier: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandBlurModifier(blur: 4, scale: 0.88, opacity: 0),
                identity: IslandBlurModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(IslandMotion.contentIn),
            removal: .modifier(
                active: IslandBlurModifier(blur: 2, scale: 0.95, opacity: 0),
                identity: IslandBlurModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(IslandMotion.contentOut)
        )
    }

    static var islandPage: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandBlurModifier(blur: 6, scale: 0.97, opacity: 0),
                identity: IslandBlurModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(.spring(response: 0.36, dampingFraction: 0.9).delay(0.04)),
            removal: .modifier(
                active: IslandBlurModifier(blur: 6, scale: 1.0, opacity: 0),
                identity: IslandBlurModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.1))
        )
    }
}

// MARK: - Buttons

/// Round glyph button with a soft hover plate and springy press.
struct IslandGlyphButton: View {
    var symbol: String
    var size: CGFloat = 30
    var font: Font = .system(size: 15, weight: .semibold)
    var tint: Color = .white
    var plate: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(Color.white.opacity(plate ? (hovering ? 0.16 : 0.08) : (hovering ? 0.1 : 0)))
                )
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

struct IslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Rounded "platter" used for cards inside the expanded island.
struct IslandCard<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }
}

extension Color {
    /// Lifts dark album colours so tinted text and bars stay legible on black.
    static func islandTint(_ ns: NSColor) -> Color {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(s, 0.85)), brightness: Double(max(b, 0.78)))
    }
}

extension View {
    /// Gentle "breathing" symbol animation where available.
    @ViewBuilder
    func islandBreathing() -> some View {
        if #available(macOS 15.0, *) {
            self.symbolEffect(.breathe, options: .repeating)
        } else {
            self.symbolEffect(.pulse, options: .repeating)
        }
    }
}
