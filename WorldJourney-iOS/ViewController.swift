import UIKit

class ViewController: UIViewController {
  var renderer: Renderer!
  
  override func viewDidLoad() {
    super.viewDidLoad()
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
