//
//  GameViewController.swift
//  CubeSphere iOS
//
//  Created by Dan Cutting on 7/1/2024.
//  Copyright © 2024 cutting.io. All rights reserved.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {
  
  var renderer: Renderer!
  var mtkView: MTKView!
  var panRecognizer: UIPanGestureRecognizer!
  var downRecognizer: UILongPressGestureRecognizer!

  override func viewDidLoad() {
    super.viewDidLoad()
    
    guard let mtkView = self.view as? MTKView else {
      print("View of Gameview controller is not an MTKView")
      return
    }
    
    // Select the device to render with.  We choose the default device
    guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
      print("Metal is not supported")
      return
    }
    
    mtkView.device = defaultDevice
    mtkView.backgroundColor = UIColor.black
    
    guard let newRenderer = Renderer(metalKitView: mtkView) else {
      print("Renderer cannot be initialized")
      return
    }
    
    renderer = newRenderer
    
    renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
    
    mtkView.delegate = renderer
    
    panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didDrag))
    mtkView.addGestureRecognizer(panRecognizer)

    downRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didHold))
    downRecognizer.minimumPressDuration = 0.2
    mtkView.addGestureRecognizer(downRecognizer)
  }
  
  @objc private func didDrag(gestureRecognizer: UIPanGestureRecognizer) {
    let translation = gestureRecognizer.translation(in: mtkView)
    print(translation)
    renderer.adjust(height: Float(translation.y / 4.0))
  }
  
  @objc private func didHold(gestureRecognizer: UILongPressGestureRecognizer) {
    switch gestureRecognizer.state {
    case .began:
      renderer.setOverheadView()
    case .cancelled, .failed, .ended:
      renderer.setGroundView()
    case .changed, .possible:
      break
    @unknown default:
      break
    }
  }
}
