import AppKit
import ServiceManagement
import os

private let log = Logger(subsystem: "com.local.stretchmate", category: "break")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum State {
        case waiting(until: Date)
        case paused(remaining: TimeInterval)
        case onBreak
    }

    private var state: State = .paused(remaining: 0)
    /// The one and only timer: fires at the next break (tolerance 30 s) or at break end.
    private var timer: Timer?
    private let overlay = OverlayController()
    private var lastExerciseIndex = -1
    private var chimeSound: NSSound?

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let countdownItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
    private let chimeItem = NSMenuItem(title: "Soft chime", action: #selector(toggleChime), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
    private let intervalMenu = NSMenu()
    private let breakMenu = NSMenu()
    private let modeMenu = NSMenu()

    private static let intervalPresets = [10, 15, 20, 25, 30, 45, 60]
    private static let breakPresets = [15, 20, 30, 45, 60, 90]

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        scheduleNextBreak()

        // Timers don't run while the Mac sleeps, so on wake/unlock we check the wall clock
        // and show any break that came due while you were away.
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)

        // Testing aids: `open -a StretchMate --args --break-now` shows a break immediately;
        // posting com.local.stretchmate.simulateReturn acts like the user coming back.
        dnc.addObserver(self, selector: #selector(simulateReturn), name: .init("com.local.stretchmate.simulateReturn"), object: nil)
        if CommandLine.arguments.contains("--break-now") { startBreak() }
    }

    // MARK: Away detection

    private var screenLocked = false
    private var displayAsleep = false
    private var activityMonitors: [Any] = []

    /// No keyboard/mouse input for this long counts as "away". Hidden default: awaySeconds.
    private var awayThreshold: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "awaySeconds")
        return v > 0 ? v : 90
    }

    private var userIsAway: Bool {
        if screenLocked || displayAsleep { return true }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                          eventType: CGEventType(rawValue: ~0)!)
        return idle >= awayThreshold
    }

    /// Only installed while a break is waiting for the user; costs nothing until input arrives.
    private func watchForReturn() {
        stopWatchingForReturn()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            let type = e.type.rawValue
            MainActor.assumeIsolated { self?.userActivity("global event \(type)") }
        }) { activityMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            let type = e.type.rawValue
            MainActor.assumeIsolated { self?.userActivity("local event \(type)") }
            return e
        }) { activityMonitors.append(l) }
    }

    private func stopWatchingForReturn() {
        activityMonitors.forEach(NSEvent.removeMonitor)
        activityMonitors.removeAll()
    }

    private func userActivity(_ source: String) {
        guard !screenLocked else { return } // typing the password doesn't count; unlock does
        userReturned(source)
    }

    private func userReturned(_ source: String) {
        guard overlay.isWaitingForUser else { return }
        log.info("user returned (\(source, privacy: .public)), starting routine")
        stopWatchingForReturn()
        overlay.start()
        if Settings.chime { playChime() }
        arm(at: Date().addingTimeInterval(stepDuration), tolerance: 0.5)
    }

    /// If a break came due while timers were frozen (sleep), show it now; otherwise re-arm
    /// against the wall clock so the countdown doesn't drift by the time spent asleep.
    private func catchUp() {
        guard case .waiting(let until) = state else { return }
        if until <= Date() {
            startBreak()
        } else {
            arm(at: until, tolerance: 30)
        }
    }

    @objc private func systemDidWake() { catchUp() }

    @objc private func screensDidWake() {
        displayAsleep = false
        catchUp()
    }

    @objc private func screensDidSleep() { displayAsleep = true }

    @objc private func screenDidLock() { screenLocked = true }

    @objc private func screenDidUnlock() {
        screenLocked = false
        displayAsleep = false
        if overlay.isWaitingForUser { userReturned("unlock") } else { catchUp() }
    }

    @objc private func simulateReturn() {
        screenLocked = false
        displayAsleep = false
        userReturned("simulated")
    }

    // MARK: Scheduling

    private func arm(at date: Date, tolerance: TimeInterval) {
        timer?.invalidate()
        let t = Timer(fireAt: date, interval: 0, target: self, selector: #selector(timerFired),
                      userInfo: nil, repeats: false)
        t.tolerance = tolerance
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func disarm() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextBreak(in seconds: TimeInterval = Settings.interval) {
        let date = Date().addingTimeInterval(seconds)
        state = .waiting(until: date)
        arm(at: date, tolerance: 30)
        updateIcon()
    }

    @objc private func timerFired() {
        switch state {
        case .waiting: startBreak()
        case .onBreak:
            if overlay.advance() {
                log.info("next step")
                arm(at: Date().addingTimeInterval(stepDuration), tolerance: 0.5)
            } else {
                endBreak()
            }
        case .paused: disarm()
        }
    }

    private var stepDuration: TimeInterval = 30

    private func startBreak() {
        if case .onBreak = state { return }
        state = .onBreak

        let exercises: [Exercise]
        switch Settings.mode {
        case .routine:
            exercises = Exercise.routine
        case .random:
            var idx: Int
            repeat { idx = Int.random(in: 0..<Exercise.all.count) } while idx == lastExerciseIndex && Exercise.all.count > 1
            lastExerciseIndex = idx
            exercises = [Exercise.all[idx]]
        }

        // The configured break length is split evenly across the exercises.
        stepDuration = Settings.breakDuration / Double(exercises.count)
        let away = userIsAway
        log.info("break due; away=\(away, privacy: .public) locked=\(self.screenLocked, privacy: .public) displayAsleep=\(self.displayAsleep, privacy: .public)")
        overlay.show(BreakSession(exercises: exercises, stepDuration: stepDuration, started: !away)) { [weak self] in
            self?.endBreak()
        }
        if away {
            // Keep the card up (static, no countdown) until the user is back.
            disarm()
            watchForReturn()
        } else {
            if Settings.chime { playChime() }
            arm(at: Date().addingTimeInterval(stepDuration), tolerance: 0.5) // step changes need to be punctual
        }
        updateIcon()
    }

    private func closeOverlay() {
        stopWatchingForReturn()
        overlay.dismiss()
        chimeSound = nil
    }

    private func endBreak() {
        guard case .onBreak = state else { return }
        closeOverlay()
        scheduleNextBreak()
        log.info("break ended; overlay closed")
    }

    private func playChime() {
        let s = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Tink"))
        s?.volume = 0.35
        s?.play()
        chimeSound = s
    }

    // MARK: Actions

    @objc private func takeBreakNow() {
        startBreak()
    }

    @objc private func snooze() {
        if case .onBreak = state { closeOverlay() }
        scheduleNextBreak(in: 5 * 60)
    }

    @objc private func togglePause() {
        switch state {
        case .paused(let remaining):
            scheduleNextBreak(in: max(remaining, 60))
        case .waiting(let until):
            disarm()
            state = .paused(remaining: until.timeIntervalSinceNow)
        case .onBreak:
            closeOverlay()
            disarm()
            state = .paused(remaining: Settings.interval)
        }
        updateIcon()
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        applyInterval(sender.tag)
    }

    @objc private func pickBreak(_ sender: NSMenuItem) {
        Settings.breakSeconds = sender.tag
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        Settings.mode = sender.tag == 0 ? .routine : .random
    }

    @objc private func customInterval() {
        if let v = askNumber(title: "Break interval", message: "Minutes between breaks:",
                             current: Settings.intervalMinutes, range: 1...240) {
            applyInterval(v)
        }
    }

    @objc private func customBreak() {
        if let v = askNumber(title: "Break length", message: "Seconds per break:",
                             current: Settings.breakSeconds, range: 5...600) {
            Settings.breakSeconds = v
        }
    }

    private func applyInterval(_ minutes: Int) {
        Settings.intervalMinutes = minutes
        switch state {
        case .waiting: scheduleNextBreak()
        case .paused: state = .paused(remaining: Settings.interval)
        case .onBreak: break // takes effect when this break ends
        }
    }

    @objc private func toggleChime() {
        Settings.chime.toggle()
        if Settings.chime { playChime() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert("Couldn't change login item", error.localizedDescription)
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        countdownItem.isEnabled = false
        menu.addItem(countdownItem)
        menu.addItem(.separator())
        menu.addItem(item("Take a break now", #selector(takeBreakNow), key: "b"))
        menu.addItem(item("Snooze 5 min", #selector(snooze), key: "s"))
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        for m in Self.intervalPresets {
            let i = item("\(m) min", #selector(pickInterval(_:)))
            i.tag = m
            intervalMenu.addItem(i)
        }
        intervalMenu.addItem(.separator())
        intervalMenu.addItem(item("Custom…", #selector(customInterval)))

        for s in Self.breakPresets {
            let i = item("\(s) sec", #selector(pickBreak(_:)))
            i.tag = s
            breakMenu.addItem(i)
        }
        breakMenu.addItem(.separator())
        breakMenu.addItem(item("Custom…", #selector(customBreak)))

        let settings = NSMenu()
        let intervalParent = NSMenuItem(title: "Break every", action: nil, keyEquivalent: "")
        intervalParent.submenu = intervalMenu
        let breakParent = NSMenuItem(title: "Break length", action: nil, keyEquivalent: "")
        breakParent.submenu = breakMenu
        let routineItem = item("Neck & shoulder routine (3 moves)", #selector(pickMode(_:)))
        routineItem.tag = 0
        modeMenu.addItem(routineItem)
        let randomItem = item("One random exercise", #selector(pickMode(_:)))
        randomItem.tag = 1
        modeMenu.addItem(randomItem)
        let modeParent = NSMenuItem(title: "Each break", action: nil, keyEquivalent: "")
        modeParent.submenu = modeMenu

        settings.addItem(intervalParent)
        settings.addItem(breakParent)
        settings.addItem(modeParent)
        settings.addItem(.separator())
        chimeItem.target = self
        settings.addItem(chimeItem)
        loginItem.target = self
        settings.addItem(loginItem)

        let settingsParent = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsParent.submenu = settings
        menu.addItem(settingsParent)
        menu.addItem(.separator())
        menu.addItem(item("Quit StretchMate", #selector(quit), key: "q"))

        statusItem.menu = menu
        updateIcon()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    /// Menu contents are refreshed only when the menu opens — no ticking label, no wakeups.
    func menuWillOpen(_ menu: NSMenu) {
        switch state {
        case .waiting(let until):
            let secs = until.timeIntervalSinceNow
            countdownItem.title = secs < 60
                ? "Next break in under a minute"
                : "Next break in \(Int((secs / 60).rounded(.up))) min"
            pauseItem.title = "Pause"
        case .paused:
            countdownItem.title = "Paused"
            pauseItem.title = "Resume"
        case .onBreak:
            countdownItem.title = overlay.isWaitingForUser ? "Break is waiting for you" : "On a break — stretch!"
            pauseItem.title = "Pause"
        }

        let interval = Settings.intervalMinutes
        let isPresetInterval = Self.intervalPresets.contains(interval)
        for i in intervalMenu.items where i.action == #selector(pickInterval(_:)) {
            i.state = i.tag == interval ? .on : .off
        }
        intervalMenu.items.last?.title = isPresetInterval ? "Custom…" : "Custom (\(interval) min)…"
        intervalMenu.items.last?.state = isPresetInterval ? .off : .on

        let brk = Settings.breakSeconds
        let isPresetBreak = Self.breakPresets.contains(brk)
        for i in breakMenu.items where i.action == #selector(pickBreak(_:)) {
            i.state = i.tag == brk ? .on : .off
        }
        breakMenu.items.last?.title = isPresetBreak ? "Custom…" : "Custom (\(brk) sec)…"
        breakMenu.items.last?.state = isPresetBreak ? .off : .on

        for i in modeMenu.items {
            i.state = (i.tag == 0) == (Settings.mode == .routine) ? .on : .off
        }

        chimeItem.state = Settings.chime ? .on : .off
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on; loginItem.title = "Start at login"
        case .requiresApproval: loginItem.state = .mixed; loginItem.title = "Start at login (needs approval)"
        default: loginItem.state = .off; loginItem.title = "Start at login"
        }
    }

    private func updateIcon() {
        let paused: Bool
        if case .paused = state { paused = true } else { paused = false }
        let name = paused ? "pause.circle.fill" : "figure.cooldown"
        let desc = paused ? "StretchMate (paused)" : "StretchMate"
        guard let button = statusItem?.button else { return }
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: desc)
            ?? NSImage(systemSymbolName: paused ? "pause.circle" : "figure.walk", accessibilityDescription: desc) {
            img.isTemplate = true
            button.image = img
            button.title = ""
        } else {
            button.image = nil
            button.title = paused ? "⏸" : "SM"
        }
        button.toolTip = desc
    }

    // MARK: Dialogs

    private func askNumber(title: String, message: String, current: Int, range: ClosedRange<Int>) -> Int? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(message) (\(range.lowerBound)–\(range.upperBound))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = String(current)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let v = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
              range.contains(v) else { return nil }
        return v
    }

    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
