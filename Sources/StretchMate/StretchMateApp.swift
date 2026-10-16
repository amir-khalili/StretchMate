import AppKit

@main
enum StretchMateMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, belt-and-braces with LSUIElement
        app.run()
    }
}
