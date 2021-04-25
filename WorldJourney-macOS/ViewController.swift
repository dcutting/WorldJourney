import AppKit

class ViewController: NSViewController {
  
  var renderer: Renderer!
  
  init() {
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func loadView() {
    renderer = Renderer()
    view = renderer.view
    newDebugGame(self)
  }
  
  @IBAction func newGame(_ sender: NSObject) {
    renderer.newGame()
  }
  
  @IBAction func newDebugGame(_ sender: NSObject) {
    renderer.newDebugGame()
  }
}
