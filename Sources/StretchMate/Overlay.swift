import AppKit
import Observation
import SwiftUI

/// Borderless key-capable panel. The app is activated while it's on screen so Esc reaches it;
/// focus goes back to the previous app on dismiss.
final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// One break: a list of exercises shown back to back, each for `stepDuration` seconds.
@MainActor
@Observable
final class BreakSession {
    let exercises: [Exercise]
    let stepDuration: TimeInterval
    var index = 0
    /// false while the break is waiting for the user to come back: static figure, no countdown.
    var started: Bool

    init(exercises: [Exercise], stepDuration: TimeInterval, started: Bool = true) {
        self.exercises = exercises
        self.stepDuration = stepDuration
        self.started = started
    }

    var current: Exercise { exercises[index] }
    var isLast: Bool { index >= exercises.count - 1 }
}

/// Owns the overlay window only while a break is on screen. Between breaks `panel` and
/// `session` are nil: no window, no hosting view, no SwiftUI state, no animations.
@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private var session: BreakSession?
    private var previousApp: NSRunningApplication?
    static let size = NSSize(width: 420, height: 320)

    var isShowing: Bool { panel != nil }
    var isWaitingForUser: Bool { session?.started == false }

    /// User is back: start animations and the countdown, and bring the card to the front.
    func start() {
        guard let s = session, !s.started else { return }
        s.started = true
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    func show(_ session: BreakSession, onSkip: @escaping () -> Void) {
        dismiss()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: vf.midX - Self.size.width / 2, y: vf.midY - Self.size.height / 2,
                           width: Self.size.width, height: Self.size.height)

        let p = OverlayPanel(contentRect: frame, styleMask: [.borderless],
                             backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = false
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.onCancel = onSkip
        p.contentView = NSHostingView(rootView: OverlayView(session: session, onSkip: onSkip))

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
        panel = p
        self.session = session
    }

    /// Moves to the next exercise. Returns false when the session is already on its last one.
    func advance() -> Bool {
        guard let s = session, !s.isLast else { return false }
        s.index += 1
        return true
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        session = nil
        p.onCancel = nil
        p.orderOut(nil)
        p.contentView = nil // tears down NSHostingView → SwiftUI views, @State and repeatForever animations
        p.close()
        if NSApp.isActive, let prev = previousApp, !prev.isTerminated {
            prev.activate()
        }
        previousApp = nil
    }
}

struct OverlayView: View {
    let session: BreakSession
    let onSkip: () -> Void

    var body: some View {
        let tint = Color(nsColor: .controlAccentColor)
        let ex = session.current
        let count = session.exercises.count

        VStack(spacing: 8) {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(count > 1 ? "STRETCH BREAK · \(session.index + 1) OF \(count)" : "STRETCH BREAK")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    if count > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<count, id: \.self) { i in
                                Circle()
                                    .fill(i <= session.index ? tint : Color.primary.opacity(0.18))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                Text(ex.title)
                    .font(.title2.weight(.bold))
            }

            // New identity per step (and on start) → the previous figure and its animation are destroyed.
            Group {
                if ex.kind == .eyes {
                    EyeBreakView(animate: session.started)
                } else {
                    FigureView(kind: ex.kind, animate: session.started)
                }
            }
            .id("\(session.index)-\(session.started)")
            .frame(height: 112)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(tint)
                            .frame(width: 10)
                        Text(step)
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .id(session.index)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if session.started {
                    StepProgressBar(duration: session.stepDuration, tint: tint)
                        .id(session.index)
                } else {
                    Label("Welcome back! Move the mouse to start.", systemImage: "hand.wave")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Skip", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Thin bar that drains once over `duration` (a single linear animation, no timer).
struct StepProgressBar: View {
    let duration: TimeInterval
    let tint: Color
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint).frame(width: g.size.width * progress)
            }
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.linear(duration: duration)) { progress = 0 }
        }
    }
}
