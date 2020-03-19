import Cocoa

let metalViewController = MetalViewController()

func mouseMoved(deltaX: Int, deltaY: Int) {
    metalViewController.mouseMoved(deltaX: Int(deltaX), deltaY: Int(deltaY))
}

@NSApplicationMain class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentViewController = metalViewController
        window.makeKeyAndOrderFront(nil)
        
        CGDisplayHideCursor(0)
        CGAssociateMouseAndMouseCursorPosition(0)

        func myCGEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {

            if [.mouseMoved].contains(type) {
                let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
                let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
                mouseMoved(deltaX: Int(deltaX), deltaY: Int(deltaY))
            }
            return Unmanaged.passRetained(event)
        }

        let eventMask = (1 << CGEventType.mouseMoved.rawValue)
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .headInsertEventTap,
                                              options: .defaultTap,
                                              eventsOfInterest: CGEventMask(eventMask),
                                              callback: myCGEventCallback,
                                              userInfo: nil) else {
                                                print("failed to create event tap")
                                                exit(1)
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        CFRunLoopRun()
    }
}
