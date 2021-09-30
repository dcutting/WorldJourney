import Metal
import MetalKit

class GBuffer {
  var terrainPipelineState: MTLRenderPipelineState!
  var oceanPipelineState: MTLRenderPipelineState!
  var terrainRenderPassDescriptor: MTLRenderPassDescriptor!
  var oceanRenderPassDescriptor: MTLRenderPassDescriptor!
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var waveNormalTexture: MTLTexture!
  var wavePositionTexture: MTLTexture!
  var depthTexture: MTLTexture!
  let closeNormalMap: MTLTexture
  let mediumNormalMap: MTLTexture
  
  var lastCameraPosition = SIMD3<Float>(x: -10000000, y: 0, z: 0)

  init(device: MTLDevice, library: MTLLibrary, maxTessellation: Int) {
    terrainPipelineState = Self.makeGBufferPipelineState(device: device, library: library, maxTessellation: maxTessellation, isOcean: false)
    oceanPipelineState = Self.makeGBufferPipelineState(device: device, library: library, maxTessellation: maxTessellation, isOcean: true)
    closeNormalMap = makeTexture(imageName: "stony_normal", device: device)
    mediumNormalMap = makeTexture(imageName: "sand_normal", device: device)
  }

  func buildGbufferTextures(device: MTLDevice, size: CGSize) {
    albedoTexture = buildTexture(device: device, pixelFormat: .bgra8Unorm, size: size, label: "Albedo texture")
    normalTexture = buildTexture(device: device, pixelFormat: .rgba16Float, size: size, label: "Normal texture")
    positionTexture = buildTexture(device: device, pixelFormat: .rgba32Float, size: size, label: "Position texture")
    waveNormalTexture = buildTexture(device: device, pixelFormat: .rgba16Float, size: size, label: "Wave Normal texture")
    wavePositionTexture = buildTexture(device: device, pixelFormat: .rgba32Float, size: size, label: "Wave Position texture")
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
  
  func makeRenderPassDescriptors(device: MTLDevice, size: CGSize) {
    buildGbufferTextures(device: device, size: size)
    makeTerrainRenderPassDescriptor(device: device, size: size)
    makeOceanRenderPassDescriptor(device: device, size: size)
  }
  
  func makeTerrainRenderPassDescriptor(device: MTLDevice, size: CGSize) {
    let gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
    
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
    gBufferRenderPassDescriptor.setUpDepthAttachment(texture: depthTexture,
                                                     loadAction: .clear,
                                                     storeAction: .store)
    self.terrainRenderPassDescriptor = gBufferRenderPassDescriptor
  }
  
  func makeOceanRenderPassDescriptor(device: MTLDevice, size: CGSize) {
    let gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
    
    // TODO: according to WWDC Metal lab engineers,
    // dontCare is probably what we want but that breaks the skybox currently.
    // Not sure how it could work.
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 0,
                                                     texture: albedoTexture,
                                                     loadAction: .load)
    
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 1,
                                                     texture: waveNormalTexture,
                                                     loadAction: .dontCare)
    gBufferRenderPassDescriptor.setUpColorAttachment(position: 2,
                                                     texture: wavePositionTexture,
                                                     loadAction: .dontCare)
    gBufferRenderPassDescriptor.setUpDepthAttachment(texture: depthTexture,
                                                     loadAction: .load,
                                                     storeAction: .dontCare)
    self.oceanRenderPassDescriptor = gBufferRenderPassDescriptor
  }
  
  private static func makeGBufferPipelineState(device: MTLDevice, library: MTLLibrary, maxTessellation: Int, isOcean: Bool) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].writeMask = isOcean ? [.red] : [.green]
    descriptor.colorAttachments[1].pixelFormat = .rgba16Float
    descriptor.colorAttachments[2].pixelFormat = .rgba32Float
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "GBuffer state"
    
    var isOcean = isOcean
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

  func renderTerrainPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, tessellator: Tessellator, compositor: Compositor, wireframe: Bool) {
    renderGBufferPass(renderEncoder: renderEncoder, pipelineState: terrainPipelineState, cullMode: .back, uniforms: uniforms, tessellator: tessellator, compositor: compositor, wireframe: wireframe)
  }
  
  func renderOceanPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, tessellator: Tessellator, compositor: Compositor, wireframe: Bool) {
    renderGBufferPass(renderEncoder: renderEncoder, pipelineState: oceanPipelineState, cullMode: .none, uniforms: uniforms, tessellator: tessellator, compositor: compositor, wireframe: wireframe)
  }
  
  private func renderGBufferPass(renderEncoder: MTLRenderCommandEncoder, pipelineState: MTLRenderPipelineState, cullMode: MTLCullMode, uniforms: Uniforms, tessellator: Tessellator, compositor: Compositor, wireframe: Bool) {
    renderEncoder.pushDebugGroup("Gbuffer pass")
    renderEncoder.label = "Gbuffer encoder"
    
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(compositor.depthStencilState)
    renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
    renderEncoder.setCullMode(wireframe ? .none : cullMode)

    var uniforms = uniforms
    let michelicLag: Float = 0
    if distance(lastCameraPosition, uniforms.cameraPosition) > michelicLag {
      lastCameraPosition = uniforms.cameraPosition
    }
    uniforms.cameraPosition = lastCameraPosition
    
    let (factors, points, _, count) = tessellator.getBuffers(uniforms: uniforms)
    var terrain = Renderer.terrain!

    renderEncoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: 0)

    renderEncoder.setVertexBuffer(points, offset: 0, index: 0)
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    renderEncoder.setVertexBytes(&terrain, length: MemoryLayout<Terrain>.stride, index: 2)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    renderEncoder.setFragmentTexture(closeNormalMap, index: 0)
    renderEncoder.setFragmentTexture(mediumNormalMap, index: 1)

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

extension MTLRenderPassDescriptor {
  func setUpDepthAttachment(texture: MTLTexture, loadAction: MTLLoadAction, storeAction: MTLStoreAction) {
    depthAttachment.texture = texture
    depthAttachment.loadAction = loadAction
    depthAttachment.storeAction = storeAction
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
