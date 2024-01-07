import Metal
import MetalKit
import SpriteKit
import GameplayKit

class Overlay {
  let menuScene: SKScene
  let sceneRenderer: SKRenderer
  
  let hudRenderPass: RenderPass!

  let overlayPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  var worldTexture: MTLTexture!
  
  var energyText = "" {
    didSet {
      energyLabel?.text = energyText
    }
  }
  var energyColour = SKColor(ciColor: .white)
  {
    didSet {
      energyLabel?.fontColor = energyColour
    }
  }
  var fpsText = "" {
    didSet {
      fpsLabel?.text = fpsText
    }
  }
  var fpsLabel: SKLabelNode?
  var energyLabel: SKLabelNode?

  var quadVerticesBuffer: MTLBuffer!
  var quadTexCoordsBuffer: MTLBuffer!
  
  let quadVertices: [Float] = [
    -1.0,  1.0,
    1.0, -1.0,
    -1.0, -1.0,
    -1.0,  1.0,
    1.0,  1.0,
    1.0, -1.0,
  ]
  
  let quadTexCoords: [Float] = [
    0.0, 0.0,
    1.0, 1.0,
    0.0, 1.0,
    0.0, 0.0,
    1.0, 0.0,
    1.0, 1.0
  ]
  
  init(device: MTLDevice, library: MTLLibrary, view: MTKView) {
    overlayPipelineState = Self.makeOverlayPipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)!
    quadVerticesBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<Float>.size * quadVertices.count, options: [])
    quadVerticesBuffer.label = "Quad vertices"
    quadTexCoordsBuffer = device.makeBuffer(bytes: quadTexCoords, length: MemoryLayout<Float>.size * quadTexCoords.count, options: [])
    quadTexCoordsBuffer.label = "Quad texCoords"

    menuScene = GKScene(fileNamed: "HUD.sks")?.rootNode as! SKScene
    energyLabel = menuScene.childNode(withName: "//energy") as? SKLabelNode
    fpsLabel = menuScene.childNode(withName: "//fps") as? SKLabelNode
    sceneRenderer = SKRenderer(device: device)
    sceneRenderer.scene = menuScene
    hudRenderPass = RenderPass(device: device, name: "HUD", size: menuScene.size)
  }

  private static func makeOverlayPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "Overlay state"
    descriptor.vertexFunction = library.makeFunction(name: "overlay_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "overlay_fragment")
    do {
      return try device.makeRenderPipelineState(descriptor: descriptor)
    } catch let error {
      fatalError(error.localizedDescription)
    }
  }

  private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
    let depthStencilDescriptor = MTLDepthStencilDescriptor()
    depthStencilDescriptor.depthCompareFunction = .less
    depthStencilDescriptor.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
  }
  
  func update(device: MTLDevice, size: CGSize) {
    hudRenderPass.updateTextures(device: device, size: size)
    menuScene.isPaused = false
    menuScene.size = size
  }
  
  func renderOverlayPass(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
    // Scene pass.
    sceneRenderer.update(atTime: CACurrentMediaTime())
    let viewPort = CGRect(origin: .zero, size: menuScene.size)
    sceneRenderer.render(withViewport: viewPort,
                         commandBuffer: commandBuffer,
                         renderPassDescriptor: hudRenderPass.descriptor)

    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!

    // Overlay.
    renderEncoder.pushDebugGroup("Overlay pass")
    renderEncoder.label = "Overlay encoder"
    renderEncoder.setRenderPipelineState(overlayPipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)

    renderEncoder.setVertexBuffer(quadVerticesBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(quadTexCoordsBuffer, offset: 0, index: 1)

    renderEncoder.setFragmentTexture(worldTexture, index: 0)
    renderEncoder.setFragmentTexture(hudRenderPass.texture, index: 1)

    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                 vertexCount: quadVertices.count)
    renderEncoder.popDebugGroup()

    renderEncoder.endEncoding()
  }
}
