import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, and the app never steals focus from the window it tiles.
app.setActivationPolicy(.accessory)
app.run()
