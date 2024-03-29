import Metal
import MetalKit

class Compositor {
  let compositionPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var waveNormalTexture: MTLTexture!
  var wavePositionTexture: MTLTexture!

  var quadVerticesBuffer: MTLBuffer!
  var quadTexCoordsBuffer: MTLBuffer!

  let renderPass: RenderPass!

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
    compositionPipelineState = Self.makeCompositionPipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)!
    quadVerticesBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<Float>.size * quadVertices.count, options: [])
    quadVerticesBuffer.label = "Quad vertices"
    quadTexCoordsBuffer = device.makeBuffer(bytes: quadTexCoords, length: MemoryLayout<Float>.size * quadTexCoords.count, options: [])
    quadTexCoordsBuffer.label = "Quad texCoords"
    
    renderPass = RenderPass(device: device, name: "Composition", size: view.bounds.size)
  }

  private static func makeCompositionPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    let renderbufferAttachment = descriptor.colorAttachments[0]
    renderbufferAttachment?.isBlendingEnabled = true
    renderbufferAttachment?.rgbBlendOperation = MTLBlendOperation.add
    renderbufferAttachment?.alphaBlendOperation = MTLBlendOperation.add
    renderbufferAttachment?.sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
    renderbufferAttachment?.sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
    renderbufferAttachment?.destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
    renderbufferAttachment?.destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "Composition state"
    descriptor.vertexFunction = library.makeFunction(name: "composition_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "composition_fragment")
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
  
  func renderCompositionPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    
    var uniforms = uniforms
    
    renderEncoder.pushDebugGroup("Composition pass")
    renderEncoder.label = "Composition encoder"
    renderEncoder.setRenderPipelineState(compositionPipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)

    renderEncoder.setVertexBuffer(quadVerticesBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(quadTexCoordsBuffer, offset: 0, index: 1)

    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    renderEncoder.setFragmentTexture(albedoTexture, index: 0)
    renderEncoder.setFragmentTexture(normalTexture, index: 1)
    renderEncoder.setFragmentTexture(positionTexture, index: 2)
    renderEncoder.setFragmentTexture(waveNormalTexture, index: 3)
    renderEncoder.setFragmentTexture(wavePositionTexture, index: 4)

    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                 vertexCount: quadVertices.count)
    renderEncoder.popDebugGroup()
  }
}
