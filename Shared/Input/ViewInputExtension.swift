import Cocoa
import MetalKit
import simd

//--- Keyboard Input ---
extension MTKView { // <<<< -----------------Replace GameView with the view name you want keyboard input on
  open override var acceptsFirstResponder: Bool { return true }
    
  open override func keyDown(with event: NSEvent) {
        Keyboard.SetKeyPressed(KeyCodes.shift.rawValue, isOn: event.modifierFlags.contains(.shift))
        Keyboard.SetKeyPressed(event.keyCode, isOn: true)
    }
    
  open override func keyUp(with event: NSEvent) {
        Keyboard.SetKeyPressed(KeyCodes.shift.rawValue, isOn: event.modifierFlags.contains(.shift))
        Keyboard.SetKeyPressed(event.keyCode, isOn: false)
    }
}

//--- Mouse Button Input ---
extension MTKView {  // <<<< -----------------Replace GameView with the view name you want keyboard input on
  open override func mouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        Mouse.ResetMouseDelta()
    }
    
  open override func mouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
    
  open override func rightMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        Mouse.ResetMouseDelta()
    }
    
  open override func rightMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
    
  open override func otherMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        Mouse.ResetMouseDelta()
    }
    
  open override func otherMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
    
}

// --- Mouse Movement ---
extension MTKView {  // <<<< -----------------Replace GameView with the view name you want keyboard input on
  open override func mouseMoved(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
  open override func scrollWheel(with event: NSEvent) {
        Mouse.ScrollMouse(deltaY: Float(event.deltaY))
    }
    
  open override func mouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
  open override func rightMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
  open override func otherMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
        
    }
    
    private func setMousePositionChanged(event: NSEvent){
        let overallLocation = SIMD2<Float>(Float(event.locationInWindow.x),
                                           Float(event.locationInWindow.y))
        let deltaChange = SIMD2<Float>(Float(event.deltaX),
                                       Float(event.deltaY))
        Mouse.SetMousePositionChange(overallPosition: overallLocation,
                                     deltaPosition: deltaChange)
    }
    
  open override func updateTrackingAreas() {
        let area = NSTrackingArea(rect: self.bounds,
                                  options: [NSTrackingArea.Options.activeAlways,
                                            NSTrackingArea.Options.mouseMoved,
                                            NSTrackingArea.Options.enabledDuringMouseDrag],
                                  owner: self,
                                  userInfo: nil)
        self.addTrackingArea(area)
    }
    
}

