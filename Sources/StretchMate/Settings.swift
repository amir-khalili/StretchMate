import Foundation

/// Thin UserDefaults wrapper. Domain: com.local.stretchmate
enum Settings {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            "intervalMinutes": 20,
            "breakSeconds": 30,
            "chime": false,
            "mode": BreakMode.routine.rawValue,
        ])
    }

    enum BreakMode: String {
        case routine  // neck rotation → neck forward & back → shoulder rolls, every break
        case random   // one random exercise from the full list
    }

    static var mode: BreakMode {
        get { BreakMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .routine }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    static var intervalMinutes: Int {
        get { max(1, defaults.integer(forKey: "intervalMinutes")) }
        set { defaults.set(max(1, newValue), forKey: "intervalMinutes") }
    }

    static var breakSeconds: Int {
        get { max(5, defaults.integer(forKey: "breakSeconds")) }
        set { defaults.set(max(5, newValue), forKey: "breakSeconds") }
    }

    static var chime: Bool {
        get { defaults.bool(forKey: "chime") }
        set { defaults.set(newValue, forKey: "chime") }
    }

    static var interval: TimeInterval { TimeInterval(intervalMinutes * 60) }
    static var breakDuration: TimeInterval { TimeInterval(breakSeconds) }
}
