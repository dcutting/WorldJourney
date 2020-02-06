import AppKit

class MetalViewController: NSViewController {
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
    }
}
