import Cocoa

@NSApplicationMain class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    let metalViewController = MetalViewController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentViewController = metalViewController
        window.makeKeyAndOrderFront(nil)
    }
}
