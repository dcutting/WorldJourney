import Metal
import MetalKit

class GBuffer {
  var gBufferPipelineState: MTLRenderPipelineState!
  var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!
  let normalMapTexture: MTLTexture
  let normalMapTexture2: MTLTexture

  init(device: MTLDevice, library: MTLLibrary, maxTessellation: Int) {
    gBufferPipelineState = Self.makeGBufferPipelineState(device: device, library: library, maxTessellation: maxTessellation)
    normalMapTexture = Self.makeTexture(imageName: "stony_normal", device: device)
    normalMapTexture2 = Self.makeTexture(imageName: "snow_normal", device: device)
  }

  private static func makeTexture(imageName: String, device: MTLDevice) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    return try! textureLoader.newTexture(name: imageName, scaleFactor: 1.0, bundle: Bundle.main, options: [.textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))])
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
    let textures: [MTLTexture] = [albedoTexture,
                                  normalTexture,
                                  positionTexture]
    for (position, texture) in textures.enumerated() {
      gBufferRenderPassDescriptor.setUpColorAttachment(position: position,
                                                       texture: texture)
    }
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
    
    descriptor.vertexFunction = library.makeFunction(name: "gbuffer_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "gbuffer_fragment")
        
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
    descriptor.tessellationControlPointIndexType = .uint32

    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  func renderGBufferPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, tessellator: Tessellator, compositor: Compositor, wireframe: Bool) {
    renderEncoder.pushDebugGroup("Gbuffer pass")
    renderEncoder.label = "Gbuffer encoder"
    
    renderEncoder.setRenderPipelineState(gBufferPipelineState)
    renderEncoder.setDepthStencilState(compositor.depthStencilState)
    renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
    renderEncoder.setCullMode(.back)

    var uniforms = uniforms

    renderEncoder.setTessellationFactorBuffer(tessellator.tessellationFactorsBuffer, offset: 0, instanceStride: 0)

    renderEncoder.setVertexBuffer(tessellator.controlPointsBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    renderEncoder.setVertexBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 2)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    renderEncoder.setFragmentTexture(normalMapTexture, index: 0)
    renderEncoder.setFragmentTexture(normalMapTexture2, index: 1)

    renderEncoder.drawIndexedPatches(numberOfPatchControlPoints: 4,
                                     patchStart: 0,
                                     patchCount: tessellator.patchCount,
                                     patchIndexBuffer: nil,
                                     patchIndexBufferOffset: 0,
                                     controlPointIndexBuffer: tessellator.patchIndexBuffer,
                                     controlPointIndexBufferOffset: 0,
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
  
  func setUpColorAttachment(position: Int, texture: MTLTexture) {
    let attachment: MTLRenderPassColorAttachmentDescriptor = colorAttachments[position]
    attachment.texture = texture
    attachment.loadAction = .clear
    attachment.storeAction = .dontCare
    attachment.clearColor = MTLClearColorMake(0, 0, 0, 0)
  }
}
