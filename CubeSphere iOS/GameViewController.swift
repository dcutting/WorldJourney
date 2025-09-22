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
    
    let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didDrag))
    mtkView.addGestureRecognizer(panRecognizer)

    let downRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didHold))
    mtkView.addGestureRecognizer(downRecognizer)

    let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
    mtkView.addGestureRecognizer(tapRecognizer)
  }
  
  @objc private func didDrag(gestureRecognizer: UIPanGestureRecognizer) {
    let translation = gestureRecognizer.translation(in: mtkView)
    renderer.set(altitude: translation.y * 10000.0)
  }
  
  @objc private func didHold(gestureRecognizer: UILongPressGestureRecognizer) {
    switch gestureRecognizer.state {
    case .began:
      renderer.diagnosticMode.toggle()
    case .possible, .changed, .ended, .cancelled, .failed:
      break
    @unknown default:
      break
    }
  }
  
  @objc private func didTap(gestureRecognizer: UITapGestureRecognizer) {
    switch gestureRecognizer.state {
    case .ended:
      renderer.overheadView.toggle()
    case .possible, .began, .changed, .cancelled, .failed:
      break
    @unknown default:
      break
    }
  }
}
