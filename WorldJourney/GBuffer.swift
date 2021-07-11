import Metal
import MetalKit

class GBuffer {
  var gBufferPipelineState: MTLRenderPipelineState!
  var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
  // TODO: may need another normal/position texture for water layer
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!
  let normalMapTexture: MTLTexture
  let normalMapTexture2: MTLTexture

  init(device: MTLDevice, library: MTLLibrary, maxTessellation: Int) {
    gBufferPipelineState = Self.makeGBufferPipelineState(device: device, library: library, maxTessellation: maxTessellation)
    normalMapTexture = makeTexture(imageName: "stony_normal", device: device)
    normalMapTexture2 = makeTexture(imageName: "snow_normal", device: device)
  }

  func buildGbufferTextures(device: MTLDevice, size: CGSize) {
    albedoTexture = buildTexture(device: device, pixelFormat: .bgra8Unorm, size: size, label: "Albedo texture")
    normalTexture = buildTexture(device: device, pixelFormat: .rgba16Float, size: size, label: "Normal texture")
    positionTexture = buildTexture(device: device, pixelFormat: .rgba32Float, size: size, label: "Position texture")
    depthTexture = buildTexture(device: device, pixelFormat: .depth32Float, size: size, label: "Depth texture")
  }
  
  func buildTexture(device: MTLDevice, pixelFormat: MTLPixelFormat, size: CGSize, label: String) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: pixelFormat,
      width: Int(size.width),
      height: Int(size.height),
      mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .private
    guard let texture =
      device.makeTexture(descriptor: descriptor) else {
        fatalError()
    }
    texture.label = "\(label) texture"
    return texture
  }
  
  func makeGBufferRenderPassDescriptor(device: MTLDevice, size: CGSize) {
    let gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
    buildGbufferTextures(device: device, size: size)
    
    // TODO: according to WWDC Metal lab engineers,
    // dontCare is probably what we want but that breaks the skybox currently.
    // Not sure how it could work.
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 0,
                                                     texture: albedoTexture,
                                                     loadAction: .clear)
    
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 1,
                                                     texture: normalTexture,
                                                     loadAction: .dontCare)
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 2,
                                                     texture: positionTexture,
                                                     loadAction: .dontCare)
    gBufferRenderPassDescriptor.setUpDepthAttachment(texture: depthTexture)
    self.gBufferRenderPassDescriptor = gBufferRenderPassDescriptor
  }
  
  private static func makeGBufferPipelineState(device: MTLDevice, library: MTLLibrary, maxTessellation: Int) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[1].pixelFormat = .rgba16Float
    descriptor.colorAttachments[2].pixelFormat = .rgba32Float
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "GBuffer state"
    
    var isOcean = false
    let constants = MTLFunctionConstantValues()
    constants.setConstantValue(&isOcean, type: .bool, index: 0)
    descriptor.vertexFunction = try! library.makeFunction(name: "gbuffer_vertex", constantValues: constants)
    descriptor.fragmentFunction = try! library.makeFunction(name: "gbuffer_fragment", constantValues: constants)
        
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    descriptor.vertexDescriptor = vertexDescriptor
    
    descriptor.tessellationFactorStepFunction = .perPatch
    descriptor.maxTessellationFactor = maxTessellation
    descriptor.tessellationPartitionMode = .fractionalEven

    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  func renderGBufferPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, tessellator: Tessellator, compositor: Compositor, wireframe: Bool) {
    renderEncoder.pushDebugGroup("Gbuffer pass")
    renderEncoder.label = "Gbuffer encoder"
    
    renderEncoder.setRenderPipelineState(gBufferPipelineState)
    renderEncoder.setDepthStencilState(compositor.depthStencilState)
    renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
    renderEncoder.setCullMode(wireframe ? .none : .back)

    var uniforms = uniforms
    
    let (factors, points, _, count) = tessellator.getBuffers(uniforms: uniforms)
    var terrain = Renderer.terrain!

    renderEncoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: 0)

    renderEncoder.setVertexBuffer(points, offset: 0, index: 0)
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    renderEncoder.setVertexBytes(&terrain, length: MemoryLayout<Terrain>.stride, index: 2)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    renderEncoder.setFragmentTexture(normalMapTexture, index: 0)
    renderEncoder.setFragmentTexture(normalMapTexture2, index: 1)

    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: count,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1,
                              baseInstance: 0)
    
    renderEncoder.popDebugGroup()
  }
}

private extension MTLRenderPassDescriptor {
  func setUpDepthAttachment(texture: MTLTexture) {
    depthAttachment.texture = texture
    depthAttachment.loadAction = .clear
    depthAttachment.storeAction = .dontCare
    depthAttachment.clearDepth = 1
  }
  
  func setUpColorAttachment(position: Int, texture: MTLTexture, loadAction: MTLLoadAction) {
    let attachment: MTLRenderPassColorAttachmentDescriptor = colorAttachments[position]
    attachment.texture = texture
    attachment.loadAction = loadAction
    attachment.storeAction = .store    // NOTE: this should help iOS work properly.
    attachment.clearColor = MTLClearColorMake(0, 0, 0, 0)
  }
}
