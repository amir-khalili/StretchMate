import Foundation

enum FigureKind {
    case neckRotation, neckNod, neckTilt, chinTuck, shoulderRoll, scapularSqueeze, eyes
    case spinalExtension, wrist, hipFlexor, posture, standingBackExtension

    /// Seconds for one swing (ping-pong) or one full cycle (loop).
    var duration: Double {
        switch self {
        case .neckRotation: 2.6
        case .neckNod: 2.4
        case .neckTilt: 2.4
        case .chinTuck: 1.6
        case .shoulderRoll: 2.4
        case .scapularSqueeze: 1.8
        case .eyes: 2.5
        case .spinalExtension: 2.2
        case .wrist: 2.0
        case .hipFlexor: 2.4
        case .posture: 2.4
        case .standingBackExtension: 3.0
        }
    }

    /// Continuous loop (0→1, jump back) instead of ease-in-out back and forth.
    var loops: Bool { self == .shoulderRoll }
}

struct Exercise {
    let title: String
    let steps: [String]
    let kind: FigureKind

    static let neckRotation = Exercise(
        title: "Neck rotation",
        steps: ["Sit tall, shoulders relaxed.",
                "Turn your head to look over your left shoulder; hold 3 s.",
                "Return to centre, then turn right. Repeat slowly."],
        kind: .neckRotation)

    static let neckNod = Exercise(
        title: "Neck forward & back",
        steps: ["Lower your chin toward your chest; hold 3 s.",
                "Slowly lift your head and look up at the ceiling.",
                "Return to neutral. Move gently, never force it."],
        kind: .neckNod)

    static let shoulderRoll = Exercise(
        title: "Shoulder rolls",
        steps: ["Lift both shoulders up toward your ears.",
                "Roll them back, gently squeezing your shoulder blades.",
                "Drop them down and around. Repeat 5 times."],
        kind: .shoulderRoll)

    static let standingBackExtension = Exercise(
        title: "Stand up: back extension",
        steps: ["Stand up, feet hip-width apart.",
                "Hands on your lower back, fingers pointing down.",
                "Gently lean back, looking up; hold 3 s. Repeat 5 times."],
        kind: .standingBackExtension)

    /// Shown on every break in "routine" mode, in this order.
    static let routine: [Exercise] = [neckRotation, neckNod, shoulderRoll, standingBackExtension]

    /// Pool for "random" mode.
    static let all: [Exercise] = routine + [
        Exercise(title: "Neck side tilts",
                 steps: ["Sit tall, shoulders down.",
                         "Tilt your right ear toward your right shoulder; hold 5 s.",
                         "Switch to the left side."],
                 kind: .neckTilt),
        Exercise(title: "Chin tucks",
                 steps: ["Look straight ahead.",
                         "Glide your chin straight back (double chin); hold 3 s.",
                         "Release and repeat 5 times."],
                 kind: .chinTuck),
        Exercise(title: "Shoulder-blade squeeze",
                 steps: ["Bend your elbows, hands at shoulder height.",
                         "Squeeze your shoulder blades together and down; hold 5 s.",
                         "Relax and repeat."],
                 kind: .scapularSqueeze),
        Exercise(title: "20-20-20 eye break",
                 steps: ["Look away from the screen.",
                         "Focus on something about 20 ft (6 m) away.",
                         "Hold for 20 seconds and blink slowly."],
                 kind: .eyes),
        Exercise(title: "Seated spinal extension",
                 steps: ["Scoot to the front of your chair.",
                         "Lift your chest and gently arch your upper back.",
                         "Breathe in deeply, then relax."],
                 kind: .spinalExtension),
        Exercise(title: "Wrist & forearm stretch",
                 steps: ["Extend one arm, palm facing out.",
                         "Gently pull your fingers back with the other hand; hold 10 s.",
                         "Switch arms."],
                 kind: .wrist),
        Exercise(title: "Standing hip flexor stretch",
                 steps: ["Stand and step one foot back into a small lunge.",
                         "Tuck your pelvis and press your hips forward; hold 10 s.",
                         "Switch legs."],
                 kind: .hipFlexor),
        Exercise(title: "Posture check",
                 steps: ["Sit all the way back in your chair.",
                         "Feet flat on the floor, knees about level with hips.",
                         "Screen at eye level, shoulders relaxed."],
                 kind: .posture),
    ]
}
