//
//  IslandBackground.swift
//  boringNotch – Dynamic Island skin
//
//  The black body of the island. The main shape uses Apple's continuous corners;
//  a second activity buds off as a bubble joined by a metaball bridge that thins
//  and pinches off as the bubble drifts away – all vector, so edges stay crisp.
//

import SwiftUI

/// Geometry of the island body that SwiftUI interpolates frame-by-frame.
struct IslandBodyGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var topGap: CGFloat
    /// Bubble radius (0 = no bubble).
    var bubbleRadius: CGFloat
    /// Distance between the island's trailing edge and the bubble's leading edge.
    /// Negative values tuck the bubble inside the island (used while it buds off / merges back).
    var bubbleGap: CGFloat
    var scale: CGFloat
    /// Flush with the screen's top edge (notch screens): square top + concave "ears".
    var flushTop: Bool = false
}

extension Path {
    /// A notch-style silhouette: square top flush with the screen edge, rounded bottom
    /// corners and small concave fillets ("ears") where it meets the menu bar.
    static func notch(_ r: CGRect, bottomRadius: CGFloat, ear: CGFloat) -> Path {
        let br = min(bottomRadius, r.height / 2, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX - ear, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + ear), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - br))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + br, y: r.maxY), radius: br)
        p.addLine(to: CGPoint(x: r.maxX - br, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - br), radius: br)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX + ear, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension IslandBodyGeometry: Animatable {
    typealias Pair = AnimatablePair
    var animatableData: Pair<Pair<CGFloat, CGFloat>, Pair<Pair<CGFloat, CGFloat>, Pair<CGFloat, Pair<CGFloat, CGFloat>>>> {
        get {
            Pair(Pair(width, height), Pair(Pair(radius, topGap), Pair(bubbleRadius, Pair(bubbleGap, scale))))
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            radius = newValue.second.first.first
            topGap = newValue.second.first.second
            bubbleRadius = newValue.second.second.first
            bubbleGap = newValue.second.second.second.first
            scale = newValue.second.second.second.second
        }
    }

    /// Island rect inside a container of the given width (top-left origin), after the hover scale.
    func mainRect(containerWidth: CGFloat) -> CGRect {
        let w = width * scale
        let h = height * scale
        return CGRect(x: (containerWidth - w) / 2, y: topGap, width: w, height: h)
    }

    func bubbleCenter(containerWidth: CGFloat) -> CGPoint {
        let main = mainRect(containerWidth: containerWidth)
        let r = bubbleRadius * scale
        return CGPoint(x: main.maxX + bubbleGap * scale + r, y: main.midY)
    }
}

/// The island's silhouette: continuous-corner body ∪ bubble ∪ metaball bridge.
/// A plain animatable `Shape`, so SwiftUI rasterises it on the GPU every frame
/// (no CPU Canvas redraws, shadow included).
struct IslandBodyShape: Shape {
    var geometry: IslandBodyGeometry

    var animatableData: IslandBodyGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let g = geometry
        let main = g.mainRect(containerWidth: rect.width)
        let radius = min(g.radius * g.scale, main.height / 2)
        let body = g.flushTop
            ? Path.notch(main, bottomRadius: radius, ear: 6)
            : Path(roundedRect: main, cornerRadius: radius, style: .continuous)

        let r2 = g.bubbleRadius * g.scale
        guard r2 > 0.2 else { return body }
        let c2 = g.bubbleCenter(containerWidth: rect.width)
        var extra = Path(ellipseIn: CGRect(x: c2.x - r2, y: c2.y - r2, width: r2 * 2, height: r2 * 2))
        let c1 = CGPoint(x: main.maxX - radius, y: main.midY)
        if let bridge = Metaball.bridge(c1: c1, r1: radius, c2: c2, r2: r2, reach: 6 * g.scale) {
            extra.addPath(bridge)
        }
        return Path(body.cgPath.union(extra.cgPath, using: .winding))
    }
}

/// Draws the island body (fill, shadow, hairline rim) and the virtual camera.
struct IslandBodyView: View {
    var geometry: IslandBodyGeometry
    var shadowOpacity: Double
    var keylineOpacity: Double
    /// Bubble radius at rest – the rim hides while a bubble is attached.
    var restingBubbleRadius: CGFloat
    /// Virtual camera lens (offset from centre, vertical centre, diameter). nil = hidden.
    var camera: (offsetX: CGFloat, centerY: CGFloat, diameter: CGFloat)? = nil

    var body: some View {
        let shape = IslandBodyShape(geometry: geometry)
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 8)
            shape
                .stroke(Color.white.opacity(geometry.bubbleRadius > 0.5 ? 0 : keylineOpacity), lineWidth: 0.6)
            if let camera {
                IslandCameraLens(diameter: camera.diameter)
                    .offset(x: camera.offsetX, y: camera.centerY - camera.diameter / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A tiny hole-punch camera, like the MacBook Pro's.
struct IslandCameraLens: View {
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.075))
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.22), Color(white: 0.02)],
                                     center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: diameter * 0.3))
                .frame(width: diameter * 0.55, height: diameter * 0.55)
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: diameter * 0.11, height: diameter * 0.11)
                .offset(x: -diameter * 0.12, y: -diameter * 0.14)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Classic two-circle metaball connector (after Hiroyuki Sato's construction).
enum Metaball {
    /// - Parameters:
    ///   - reach: how far past touching the bridge survives before it pinches off.
    static func bridge(c1: CGPoint, r1: CGFloat, c2: CGPoint, r2: CGFloat, reach: CGFloat) -> Path? {
        let d = hypot(c2.x - c1.x, c2.y - c1.y)
        let touching = r1 + r2
        let maxDist = touching + reach
        guard r1 > 0, r2 > 0, d < maxDist, d > abs(r1 - r2) + 0.01 else { return nil }

        // Spread fades to zero as the gap approaches `reach`, so the neck thins smoothly.
        let v: CGFloat = d <= touching ? 0.5 : 0.5 * pow(1 - (d - touching) / reach, 1.4)
        guard v > 0.002 else { return nil }

        var u1: CGFloat = 0, u2: CGFloat = 0
        if d < touching {
            u1 = acos(min(1, max(-1, (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))))
            u2 = acos(min(1, max(-1, (r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))))
        }
        let between = atan2(c2.y - c1.y, c2.x - c1.x)
        let maxSpread = acos(min(1, max(-1, (r1 - r2) / d)))

        let a1 = between + u1 + (maxSpread - u1) * v
        let a2 = between - u1 - (maxSpread - u1) * v
        let a3 = between + .pi - u2 - (.pi - u2 - maxSpread) * v
        let a4 = between - .pi + u2 + (.pi - u2 - maxSpread) * v

        func vec(_ c: CGPoint, _ a: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        let p1 = vec(c1, a1, r1), p2 = vec(c1, a2, r1)
        let p3 = vec(c2, a3, r2), p4 = vec(c2, a4, r2)

        let handleSize: CGFloat = 2.4
        let total = r1 + r2
        let d2Base = min(v * handleSize, hypot(p3.x - p1.x, p3.y - p1.y) / total)
        let d2 = d2Base * min(1, d * 2 / total)
        let h1 = vec(p1, a1 - .pi / 2, r1 * d2)
        let h2 = vec(p2, a2 + .pi / 2, r1 * d2)
        let h3 = vec(p3, a3 + .pi / 2, r2 * d2)
        let h4 = vec(p4, a4 - .pi / 2, r2 * d2)

        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: h1, control2: h3)
        path.addLine(to: c2)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: h4, control2: h2)
        path.addLine(to: c1)
        path.closeSubpath()
        return path
    }
}

/// Clip shape for the island's content. Uses the same animatable geometry as the body,
/// so content is always clipped to exactly the black shape on every frame of a spring.
struct IslandMainShape: Shape {
    var geometry: IslandBodyGeometry

    var animatableData: IslandBodyGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let main = geometry.mainRect(containerWidth: rect.width)
        let radius = min(geometry.radius * geometry.scale, main.height / 2)
        return geometry.flushTop
            ? Path.notch(main, bottomRadius: radius, ear: 0)
            : Path(roundedRect: main, cornerRadius: radius, style: .continuous)
    }
}
