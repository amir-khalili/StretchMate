import SwiftUI

// MARK: - SwiftUI views

/// Animated stick figure. A single `t` (0…1) drives every pose; SwiftUI interpolates it
/// through `animatableData`, so no timers or TimelineView are involved. When the view is
/// removed from the hierarchy the repeating animation goes away with it.
struct FigureView: View {
    let kind: FigureKind
    var animate = true
    @State private var t: Double = 0

    var body: some View {
        let tint = Color(nsColor: .controlAccentColor)
        ZStack {
            FigurePart(kind: kind, part: .accent, t: t)
                .stroke(Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            FigurePart(kind: kind, part: .body, t: t)
                .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            FigurePart(kind: kind, part: .head, t: t)
                .fill(tint)
            FigurePart(kind: kind, part: .face, t: t)
                .fill(Color.white.opacity(0.95))
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard animate else { t = 0.5; return } // static mid-pose while waiting
            let anim: Animation = kind.loops
                ? .linear(duration: kind.duration).repeatForever(autoreverses: false)
                : .easeInOut(duration: kind.duration).repeatForever(autoreverses: true)
            withAnimation(anim) { t = 1 }
        }
    }
}

/// 20-20-20: an eye, a dashed sight line and a far-away mountain, with a dot travelling out.
struct EyeBreakView: View {
    var animate = true
    @State private var go = false

    var body: some View {
        let tint = Color(nsColor: .controlAccentColor)
        HStack(spacing: 0) {
            Image(systemName: "eye").font(.system(size: 44, weight: .regular))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                        p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2))
                    }
                    .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 7]))
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                        .scaleEffect(go ? 0.5 : 1)
                        .offset(x: go ? g.size.width - 10 : 0)
                        .opacity(go ? 0.25 : 1)
                }
            }
            .padding(.horizontal, 14)
            Image(systemName: "mountain.2").font(.system(size: 44, weight: .regular))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 24)
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: FigureKind.eyes.duration).repeatForever(autoreverses: false)) { go = true }
        }
    }
}

// MARK: - Shape

struct FigurePart: Shape {
    enum Part { case body, head, face, accent }
    let kind: FigureKind
    let part: Part
    var t: Double

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let d = FigureGeometry.drawing(kind, t)
        let s = min(rect.width, rect.height) / 100
        let xf = CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                   tx: rect.midX - 50 * s, ty: rect.midY - 50 * s)
        switch part {
        case .body: return d.body.applying(xf)
        case .head: return d.head.applying(xf)
        case .face: return d.face.applying(xf)
        case .accent: return d.accent.applying(xf)
        }
    }
}

// MARK: - Geometry (100×100 unit space, y down)

enum FigureGeometry {
    struct Drawing {
        var body = Path()
        var head = Path()
        var face = Path()   // eyes/nose drawn on top of the filled head
        var accent = Path()
    }

    static let headR: CGFloat = 10

    static func drawing(_ kind: FigureKind, _ t: Double) -> Drawing {
        var d = Drawing()
        switch kind {
        case .neckRotation: neckRotation(&d, t)
        case .neckNod: neckNod(&d, t)
        case .neckTilt: neckTilt(&d, t)
        case .chinTuck: chinTuck(&d, t)
        case .shoulderRoll: shoulderRoll(&d, t)
        case .scapularSqueeze: scapular(&d, t)
        case .spinalExtension: seated(&d, t, monitor: false)
        case .posture: seated(&d, t, monitor: true)
        case .wrist: wrist(&d, t)
        case .hipFlexor: hipFlexor(&d, t)
        case .standingBackExtension: standingBackExtension(&d, t)
        case .eyes: break // drawn by EyeBreakView
        }
        return d
    }

    // Front-facing upper body.
    private static func front(_ d: inout Drawing, head: CGPoint, neckTop: CGPoint,
                              ls: CGPoint, rs: CGPoint, le: CGPoint, re: CGPoint,
                              lh: CGPoint, rh: CGPoint) {
        let mid = P(50, (ls.y + rs.y) / 2 - 2)
        d.head.circle(head, headR)
        d.body.poly(neckTop, mid)
        d.body.poly(ls, mid, rs)
        d.body.poly(mid, P(50, 82))
        d.body.poly(P(41, 82), P(59, 82))
        d.body.poly(ls, le, lh)
        d.body.poly(rs, re, rh)
    }

    /// Side-view head facing right, with a small nose so the direction reads.
    /// `degrees` > 0 tips the face down, < 0 tips it up.
    private static func sideHead(_ d: inout Drawing, _ c: CGPoint, degrees: Double = 0) {
        d.head.circle(c, headR)
        let nose = [P(c.x + 9, c.y - 1), P(c.x + 13, c.y + 2), P(c.x + 9, c.y + 3)]
            .map { rotate($0, around: c, degrees: degrees) }
        d.body.poly(nose[0], nose[1], nose[2])
        d.face.circle(rotate(P(c.x + 5, c.y - 3), around: c, degrees: degrees), 1.6)
    }

    /// Front view, head turning left↔right. Eyes and nose sit on a sphere and slide across
    /// the face; the far eye disappears as it turns away.
    private static func neckRotation(_ d: inout Drawing, _ t: Double) {
        let c = P(50, 28)
        front(&d, head: c, neckTop: P(50, 36),
              ls: P(30, 48), rs: P(70, 48),
              le: P(26, 66), re: P(74, 66),
              lh: P(28, 84), rh: P(72, 84))
        let theta = (t - 0.5) * 140 * .pi / 180 // ±70°
        for phi in [-0.5, 0.5] {
            let a = theta + phi
            if cos(a) > 0.2 { d.face.circle(P(c.x + 8.5 * sin(a), c.y - 2), 1.7) }
        }
        d.face.circle(P(c.x + 9 * sin(theta), c.y + 3.5), 1.3)
        // turning arc above the head
        d.accent.move(to: P(35, 13)); d.accent.addQuadCurve(to: P(65, 13), control: P(50, 4))
        d.accent.poly(P(31, 10), P(35, 13), P(32, 17))
        d.accent.poly(P(69, 10), P(65, 13), P(68, 17))
    }

    /// Side view, chin down to chest ↔ looking up at the ceiling.
    private static func neckNod(_ d: inout Drawing, _ t: Double) {
        let pivot = P(48, 41)
        let a = lerp(28, -32, t)
        let shoulder = P(48, 48)
        sideHead(&d, rotate(P(51, 27), around: pivot, degrees: a), degrees: a)
        d.body.poly(rotate(P(49, 36), around: pivot, degrees: a), shoulder, P(46, 84))
        d.body.poly(shoulder, P(50, 66), P(60, 76))
        // up/down arc in front of the face
        d.accent.move(to: P(74, 12)); d.accent.addQuadCurve(to: P(74, 46), control: P(86, 29))
        d.accent.poly(P(70, 15), P(74, 12), P(77, 16))
        d.accent.poly(P(70, 43), P(74, 46), P(77, 42))
    }

    private static func neckTilt(_ d: inout Drawing, _ t: Double) {
        let pivot = P(50, 44)
        let angle = (t - 0.5) * 44
        front(&d,
              head: rotate(P(50, 28), around: pivot, degrees: angle),
              neckTop: rotate(P(50, 36), around: pivot, degrees: angle),
              ls: P(30, 48), rs: P(70, 48),
              le: P(26, 66), re: P(74, 66),
              lh: P(28, 84), rh: P(72, 84))
        d.accent.dashed(P(50, 8), P(50, 40), segments: 9)
    }

    private static func shoulderRoll(_ d: inout Drawing, _ t: Double) {
        let a = t * 2 * .pi
        let dy = -5 * sin(a)
        let dx = 2.5 * cos(a)
        front(&d,
              head: P(50, 28), neckTop: P(50, 36),
              ls: P(30 + dx, 48 + dy), rs: P(70 - dx, 48 + dy),
              le: P(26 + dx * 0.5, 66 + dy * 0.5), re: P(74 - dx * 0.5, 66 + dy * 0.5),
              lh: P(28, 84), rh: P(72, 84))
        d.accent.move(to: P(20, 46)); d.accent.addQuadCurve(to: P(37, 44), control: P(26, 32))
        d.accent.move(to: P(80, 46)); d.accent.addQuadCurve(to: P(63, 44), control: P(74, 32))
    }

    private static func scapular(_ d: inout Drawing, _ t: Double) {
        front(&d,
              head: P(50, 28), neckTop: P(50, 36),
              ls: P(30, 48), rs: P(70, 48),
              le: P(19 + 5 * t, 62 + 3 * t), re: P(81 - 5 * t, 62 + 3 * t),
              lh: P(20 + 3 * t, 40 + 2 * t), rh: P(80 - 3 * t, 40 + 2 * t))
        // shoulder blades drawing together
        d.accent.poly(P(41 + 4 * t, 54), P(43 + 4 * t, 66))
        d.accent.poly(P(59 - 4 * t, 54), P(57 - 4 * t, 66))
    }

    private static func chinTuck(_ d: inout Drawing, _ t: Double) {
        let head = P(55 - 8 * t, 28)
        let shoulder = P(48, 48)
        sideHead(&d, head)
        d.body.poly(P(head.x - 4, 36), shoulder, P(46, 84))
        d.body.poly(shoulder, P(50, 66), P(60, 76))
        // ear-over-shoulder reference line
        d.accent.dashed(P(48, 8), P(48, 46), segments: 11)
    }

    private static func seated(_ d: inout Drawing, _ t: Double, monitor: Bool) {
        let hip = P(42, 72)
        let shoulder = lerp(P(55, 49), P(44, 42), t)
        let spineCtrl = P(lerp(30, 42, t), lerp(58, 57, t))
        let head = lerp(P(63, 37), P(46, 27), t)

        sideHead(&d, head)
        d.body.move(to: hip)
        d.body.addQuadCurve(to: shoulder, control: spineCtrl)
        d.body.poly(shoulder, lerp(shoulder, head, 0.55))
        d.body.poly(shoulder, lerp(P(60, 62), P(52, 60), t), P(62, 70))
        d.body.poly(hip, P(64, 72), P(64, 92), P(73, 92))

        // chair + floor
        d.accent.poly(P(30, 40), P(32, 76), P(58, 76))
        d.accent.poly(P(34, 76), P(34, 94))
        d.accent.poly(P(56, 76), P(56, 94))
        d.accent.poly(P(24, 95), P(96, 95))

        if monitor {
            d.accent.poly(P(76, 17), P(95, 17), P(95, 35), P(76, 35), P(76, 17))
            d.accent.poly(P(85.5, 35), P(85.5, 46))
            d.accent.poly(P(72, 46), P(98, 46))
            d.accent.dashed(P(60, 26), P(75, 26), segments: 5)
        }
    }

    private static func wrist(_ d: inout Drawing, _ t: Double) {
        let head = P(36, 26)
        let shoulder = P(38, 44)
        let wrist = P(76, 44)
        let handEnd = rotate(P(88, 44), around: wrist, degrees: -72 * t) // fingers pulled back (up)
        sideHead(&d, head)
        d.body.poly(P(37, 36), shoulder, P(37, 84))
        d.body.poly(shoulder, wrist, handEnd)
        let grip = lerp(wrist, handEnd, 0.7)
        d.body.poly(shoulder, P(56, 60), P(grip.x + 3, grip.y + 1))
        d.accent.poly(P(37, 84), P(32, 95))
        d.accent.poly(P(37, 84), P(44, 95))
    }

    private static func hipFlexor(_ d: inout Drawing, _ t: Double) {
        let hip = P(46 + 8 * t, 64 + 1.5 * t)
        let shoulder = P(hip.x - 2, hip.y - 30)
        sideHead(&d, P(shoulder.x + 1, shoulder.y - 15))
        d.body.poly(P(shoulder.x + 0.5, shoulder.y - 6), shoulder, hip)
        d.body.poly(hip, P(70, 68), P(72, 93), P(80, 93))          // front leg
        d.body.poly(hip, P(32, 80), P(18, 92), P(12, 93))          // back leg, heel up
        d.body.poly(shoulder, P(shoulder.x - 7, shoulder.y + 15), P(hip.x + 2, hip.y - 6)) // hand on hip
        d.accent.poly(P(6, 95), P(94, 95))
    }

    /// Side view, standing with hands on the lower back, leaning back from the hips.
    private static func standingBackExtension(_ d: inout Drawing, _ t: Double) {
        let hip = P(50, 62)
        let a = -22 * t // negative = top of the body moves back (left)
        let r = { (p: CGPoint) in rotate(p, around: hip, degrees: a) }
        let shoulder = r(P(50, 36))
        sideHead(&d, r(P(51, 21)), degrees: a)
        d.body.poly(r(P(50.5, 29)), shoulder)                                    // neck
        d.body.move(to: hip); d.body.addQuadCurve(to: shoulder, control: r(P(54, 49))) // arched spine
        d.body.poly(shoulder, r(P(40, 47)), r(P(46, 58)))                        // hand on lower back
        d.body.poly(hip, P(48, 78), P(47, 93), P(54, 93))                        // legs
        // backward arc + floor
        d.accent.move(to: P(26, 6)); d.accent.addQuadCurve(to: P(9, 24), control: P(13, 8))
        d.accent.poly(P(8, 19), P(9, 24), P(14, 23))
        d.accent.poly(P(14, 95), P(86, 95))
    }
}

// MARK: - Helpers

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}

private func rotate(_ p: CGPoint, around c: CGPoint, degrees: Double) -> CGPoint {
    let r = degrees * .pi / 180
    let dx = p.x - c.x, dy = p.y - c.y
    return CGPoint(x: c.x + dx * cos(r) - dy * sin(r), y: c.y + dx * sin(r) + dy * cos(r))
}

private extension Path {
    mutating func poly(_ pts: CGPoint...) {
        guard let first = pts.first else { return }
        move(to: first)
        for p in pts.dropFirst() { addLine(to: p) }
    }

    mutating func circle(_ c: CGPoint, _ r: CGFloat) {
        addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    mutating func dashed(_ a: CGPoint, _ b: CGPoint, segments n: Int) {
        for i in stride(from: 0, to: n, by: 2) {
            move(to: lerp(a, b, Double(i) / Double(n)))
            addLine(to: lerp(a, b, Double(i + 1) / Double(n)))
        }
    }
}
