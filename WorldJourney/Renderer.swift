import Metal
import MetalKit

class GameView: MTKView {}

class Renderer: NSObject {
  
  let device: MTLDevice
  let view: MTKView
  let tessellationPipelineState: MTLComputePipelineState
  let heightPipelineState: MTLComputePipelineState
  let renderPipelineState: MTLRenderPipelineState
  let gBufferPipelineState: MTLRenderPipelineState
  let compositionPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
  let controlPointsBuffer: MTLBuffer
  let commandQueue: MTLCommandQueue
  var frameCounter = 0
  var surfaceDistance: Float = Float(TERRAIN_SIZE) * 1.5
  let wireframe = false
  let deferredRendering = true
  
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition = simd_float2(0, 0)
  
  var lightPosition = simd_float3(Float(-TERRAIN_SIZE*2), Float(TERRAIN_SIZE / 3), 0.0)
  
  let heightMap: MTLTexture
  let noiseMap: MTLTexture
  let normalMap: MTLTexture
  let rockTexture: MTLTexture
  let snowTexture: MTLTexture

  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!

  let avatar = AvatarPhysicsBody(mass: 1e2)
  lazy var bodySystem = BodySystem(avatar: avatar)

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

  var edgeFactors: [Float] = [4]
  var insideFactors: [Float] = [4]
  
  let patches = (horizontal: Int(PATCH_SIDE), vertical: Int(PATCH_SIDE))
  var patchCount: Int { patches.horizontal * patches.vertical }
  
  lazy var tessellationFactorsBuffer: MTLBuffer? = {
    let count = patchCount * (4 + 2)  // 4 edges + 2 insides
    let size = count * MemoryLayout<Float>.size / 2 // "half floats"
    return device.makeBuffer(length: size, options: .storageModePrivate)
  }()
  
  static let maxTessellation: Int = {
    #if os(macOS)
    return 64
    #else
    return 16
    #endif
  } ()

  static var terrainSize: Float = Float(TERRAIN_SIZE)
  static var terrainHeight: Float = Float(TERRAIN_HEIGHT)
  static var terrain = Terrain(
    size: terrainSize,
    height: terrainHeight,
    tessellation: Int32(maxTessellation),
    fractal: Fractal(
      octaves: 3,
      frequency: Float(TERRAIN_SIZE) * 0.000006,
      amplitude: terrainHeight * 0.8,
      lacunarity: 2.0,
      persistence: 0.5
    )
  )

  override init() {
    device = Renderer.makeDevice()
    view = Renderer.makeView(device: device)
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 178.0/255.0, blue: 228.0/255.0, alpha: 1.0)
    let library = device.makeDefaultLibrary()!
    tessellationPipelineState = Renderer.makeComputePipelineState(device: device, library: library)
    heightPipelineState = Renderer.makeHeightPipelineState(device: device, library: library)
    renderPipelineState = Renderer.makeRenderPipelineState(device: device, library: library, metalView: view)
    gBufferPipelineState = Renderer.makeGBufferPipelineState(device: device, library: library, metalView: view)
    compositionPipelineState = Renderer.makeCompositionPipelineState(device: device, library: library, metalView: view)
    depthStencilState = Renderer.makeDepthStencilState(device: device)!
    controlPointsBuffer = Renderer.makeControlPointsBuffer(patches: patches, terrain: Renderer.terrain, device: device)
    commandQueue = device.makeCommandQueue()!
    heightMap = Renderer.makeTexture(imageName: "hilly", device: device)
    noiseMap = Renderer.makeTexture(imageName: "noise", device: device)
    normalMap = Renderer.makeTexture(imageName: "scratched", device: device)
    rockTexture = Renderer.makeTexture(imageName: "rock", device: device)
    snowTexture = Renderer.makeTexture(imageName: "snow", device: device)
    super.init()
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size)
    quadVerticesBuffer = device.makeBuffer(bytes: quadVertices,
                                                    length: MemoryLayout<Float>.size * quadVertices.count, options: [])
    quadVerticesBuffer.label = "Quad vertices"
    quadTexCoordsBuffer = device.makeBuffer(bytes: quadTexCoords,
                                                     length: MemoryLayout<Float>.size * quadTexCoords.count, options: [])
    quadTexCoordsBuffer.label = "Quad texCoords"

    avatar.position = SIMD3<Float>(0, 2000, 0)
  }
  
  private static func makeDevice() -> MTLDevice {
    MTLCreateSystemDefaultDevice()!
  }
  
  private static func makeView(device: MTLDevice) -> MTKView {
    let metalView = GameView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
    metalView.device = device
    metalView.preferredFramesPerSecond = 60
    metalView.colorPixelFormat = .bgra8Unorm
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.framebufferOnly = true
    return metalView
  }
  
  private static func makeComputePipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "eden_tessellation"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Tessellation shader function not found.") }
    return state
  }
  
  private static func makeHeightPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "eden_height"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Height shader function not found.") }
    return state
  }
  
  private static func makeRenderPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    guard
      let vertexProgram = library.makeFunction(name: "eden_vertex"),
      let fragmentProgram = library.makeFunction(name: "eden_fragment")
      else { fatalError("Vertex/fragment shader not found.") }
    
    let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
    pipelineStateDescriptor.vertexFunction = vertexProgram
    pipelineStateDescriptor.fragmentFunction = fragmentProgram
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    pipelineStateDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
    
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
    
    pipelineStateDescriptor.tessellationFactorStepFunction = .perPatch
    pipelineStateDescriptor.maxTessellationFactor = Renderer.maxTessellation
    pipelineStateDescriptor.tessellationPartitionMode = .pow2

    return try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
  }
  
  func buildGbufferTextures(device: MTLDevice, size: CGSize) {
    albedoTexture = buildTexture(device: device, pixelFormat: .bgra8Unorm,
                                 size: size, label: "Albedo texture")
    normalTexture = buildTexture(device: device, pixelFormat: .rgba16Float,
                                 size: size, label: "Normal texture")
    positionTexture = buildTexture(device: device, pixelFormat: .rgba32Float,
                                   size: size, label: "Position texture")
    depthTexture = buildTexture(device: device, pixelFormat: .depth32Float,
                                size: size, label: "Depth texture")
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
  
  func makeGBufferRenderPassDescriptor(device: MTLDevice, size: CGSize) -> MTLRenderPassDescriptor {
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
    return gBufferRenderPassDescriptor
  }
  
  private static func makeGBufferPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[1].pixelFormat = .rgba16Float
    descriptor.colorAttachments[2].pixelFormat = .rgba32Float
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "GBuffer state"
    
    descriptor.vertexFunction = library.makeFunction(name: "eden_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "gbuffer_fragment")
        
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    descriptor.vertexDescriptor = vertexDescriptor
    
    descriptor.tessellationFactorStepFunction = .perPatch
    descriptor.maxTessellationFactor = Renderer.maxTessellation
    descriptor.tessellationPartitionMode = .fractionalEven

    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  private static func makeCompositionPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
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
  
  private static func makeControlPointsBuffer(patches: (Int, Int), terrain: Terrain, device: MTLDevice) -> MTLBuffer {
    let controlPoints = createControlPoints(patches: patches, size: (width: terrain.size, height: terrain.size))
    return device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!
  }
  
  private static func makeTexture(imageName: String, device: MTLDevice) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    return try! textureLoader.newTexture(name: imageName, scaleFactor: 2.0, bundle: Bundle.main, options: nil)
  }

  private func makeModelMatrix() -> float4x4 {
    let angle: Float = 0//Float(frameCounter) / Float(view.preferredFramesPerSecond) / 5
    let spin = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.0), by: -angle)
    return spin
  }
  
  private func makeViewMatrix(avatar: AvatarPhysicsBody) -> float4x4 {
    look(direction: avatar.look, eye: avatar.position, up: avatar.up)
  }

  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 15000.0)
  }

  private func updateBodies() {
    
    let shift = Keyboard.IsKeyPressed(.shift)
    bodySystem.scale = shift ? 10 : 1
    
      if Keyboard.IsKeyPressed(KeyCodes.w) || Keyboard.IsKeyPressed(KeyCodes.upArrow) {
          bodySystem.forward()
      }
      if Keyboard.IsKeyPressed(KeyCodes.s) || Keyboard.IsKeyPressed(KeyCodes.downArrow) {
          bodySystem.back()
      }
      if Keyboard.IsKeyPressed(KeyCodes.a) || Keyboard.IsKeyPressed(KeyCodes.leftArrow) {
          bodySystem.strafeLeft()
      }
      if Keyboard.IsKeyPressed(KeyCodes.d) || Keyboard.IsKeyPressed(KeyCodes.rightArrow) {
          bodySystem.strafeRight()
      }
      if Keyboard.IsKeyPressed(KeyCodes.e) || Keyboard.IsKeyPressed(KeyCodes.space) {
          bodySystem.boost()
      }
      if Keyboard.IsKeyPressed(KeyCodes.q) {
          bodySystem.fall()
      }
      if Keyboard.IsKeyPressed(KeyCodes.j) {
          bodySystem.turnLeft()
      }
      if Keyboard.IsKeyPressed(KeyCodes.l) {
          bodySystem.turnRight()
      }
      if Keyboard.IsKeyPressed(KeyCodes.i) {
          bodySystem.turnDown()
      }
      if Keyboard.IsKeyPressed(KeyCodes.k) {
          bodySystem.turnUp()
      }
      if Keyboard.IsKeyPressed(KeyCodes.u) {
          bodySystem.rollLeft()
      }
      if Keyboard.IsKeyPressed(KeyCodes.o) {
          bodySystem.rollRight()
      }
      if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
          bodySystem.halt()
      }
    
    bodySystem.update()
  }

  func renderGBufferPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    renderEncoder.pushDebugGroup("Gbuffer pass")
    renderEncoder.label = "Gbuffer encoder"
    
    renderEncoder.setRenderPipelineState(gBufferPipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
    renderEncoder.setCullMode(.back)

    var uniforms = uniforms

    renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)

    renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    renderEncoder.setVertexBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 2)
    renderEncoder.setVertexTexture(heightMap, index: 0)
    renderEncoder.setVertexTexture(noiseMap, index: 1)
    renderEncoder.setFragmentTexture(normalMap, index: 0)

    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: patchCount,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1,
                              baseInstance: 0)
    
    renderEncoder.endEncoding()

    renderEncoder.popDebugGroup()
  }
  
  func renderCompositionPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    
    var uniforms = uniforms
    
    renderEncoder.pushDebugGroup("Composition pass")
    renderEncoder.label = "Composition encoder"
    renderEncoder.setRenderPipelineState(compositionPipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    // 1
    renderEncoder.setVertexBuffer(quadVerticesBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(quadTexCoordsBuffer, offset: 0, index: 1)
    // 2
    renderEncoder.setFragmentTexture(albedoTexture, index: 0)
    renderEncoder.setFragmentTexture(normalTexture, index: 1)
    renderEncoder.setFragmentTexture(positionTexture, index: 2)
//    renderEncoder.setFragmentBuffer(lightsBuffer, offset: 0, index: 2)

    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    renderEncoder.setFragmentTexture(rockTexture, index: 3)
//    renderEncoder.setFragmentTexture(snowTexture, index: 4)

    renderEncoder.setFragmentTexture(heightMap, index: 5)
    renderEncoder.setFragmentTexture(noiseMap, index: 6)
    renderEncoder.setFragmentTexture(normalMap, index: 7)

    // 3
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                 vertexCount: quadVertices.count)
    renderEncoder.endEncoding()
    renderEncoder.popDebugGroup()
  }
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    gBufferRenderPassDescriptor = makeGBufferRenderPassDescriptor(device: device, size: size)
  }
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable
      else { return }
    
    frameCounter += 1
    updateBodies()
    
    let commandBuffer = commandQueue.makeCommandBuffer()!

    let modelMatrix = makeModelMatrix()
    let viewMatrix = makeViewMatrix(avatar: avatar)
    let projectionMatrix = makeProjectionMatrix()
    
    let lp = Float(frameCounter) / 600.0
    lightPosition = simd_float3(cos(lp) * Renderer.terrain.size, 2000, sin(lp) * Renderer.terrain.size)
    
    var uniforms = Uniforms(
      cameraPosition: avatar.position,
      modelMatrix: modelMatrix,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      mvpMatrix: projectionMatrix * viewMatrix * modelMatrix,
      lightPosition: lightPosition
    )
        
    // Tessellation pass.
    
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setTexture(heightMap, index: 0)
    computeEncoder.setTexture(noiseMap, index: 1)
    computeEncoder.setBytes(&edgeFactors, length: MemoryLayout<Float>.size * edgeFactors.count, index: 0)
    computeEncoder.setBytes(&insideFactors, length: MemoryLayout<Float>.size * insideFactors.count, index: 1)
    computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
    let width = min(patchCount, tessellationPipelineState.threadExecutionWidth)
    computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 3)
    computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
    computeEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 5)
    
    computeEncoder.dispatchThreads(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
    computeEncoder.endEncoding()
    
    
    if deferredRendering {

      // GBuffer pass.
      let gBufferEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBufferRenderPassDescriptor)!
      renderGBufferPass(renderEncoder: gBufferEncoder, uniforms: uniforms)

      // Composition pass.
      let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
      renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)

    } else {
      
      // Render pass.
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
      renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
      renderEncoder.setCullMode(.back)
      renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)
      renderEncoder.setDepthStencilState(depthStencilState)
      renderEncoder.setRenderPipelineState(renderPipelineState)
      
      renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: 0)
      renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      renderEncoder.setVertexBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 2)
      renderEncoder.setVertexTexture(heightMap, index: 0)
      renderEncoder.setVertexTexture(noiseMap, index: 1)
      
      renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
      renderEncoder.setFragmentBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
      renderEncoder.setFragmentTexture(rockTexture, index: 0)
      renderEncoder.setFragmentTexture(snowTexture, index: 1)
      renderEncoder.setFragmentTexture(heightMap, index: 2)
      renderEncoder.setFragmentTexture(noiseMap, index: 3)

      renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                                patchStart: 0,
                                patchCount: patchCount,
                                patchIndexBuffer: nil,
                                patchIndexBufferOffset: 0,
                                instanceCount: 1,
                                baseInstance: 0)
      
      renderEncoder.endEncoding()
    }
        

    commandBuffer.present(drawable)
    
    var groundLevel: Float = 0
    let groundLevelBuffer = device.makeBuffer(bytes: &groundLevel, length: MemoryLayout<Float>.stride, options: [])!
    var xz = avatar.position.xz
    
    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    heightEncoder.setComputePipelineState(heightPipelineState)
    heightEncoder.setTexture(heightMap, index: 0)
    heightEncoder.setTexture(noiseMap, index: 1)
    heightEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 0)
    heightEncoder.setBytes(&xz, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    heightEncoder.setBuffer(groundLevelBuffer, offset: 0, index: 2)
    heightEncoder.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
    heightEncoder.endEncoding()
    
    var timeDiff: CFTimeInterval = 0
    var positionDiff = simd_float2(0.0, 0.0)
    commandBuffer.addCompletedHandler { buffer in
      let end = buffer.gpuEndTime
      timeDiff = end - self.lastGPUEndTime
      self.lastGPUEndTime = end
      positionDiff = self.lastPosition - self.avatar.position.xz
      self.lastPosition = simd_float2(self.avatar.position.xz)
    }
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    let nsData = NSData(bytesNoCopy: groundLevelBuffer.contents(),
                        length: groundLevelBuffer.length,
                        freeWhenDone: false)
    nsData.getBytes(&groundLevel, length: groundLevelBuffer.length)

    bodySystem.fix(groundLevel: groundLevel+2)
    if (frameCounter % 30 == 0) {
      let fps = 1.0 / timeDiff
      let distance = length(positionDiff)
      let speed = Double(distance) / timeDiff * 60 * 60 / 1000.0
      print(String(format: "FPS: %.1f, Ground: %.1f m, Avatar: %.1f m, Altitude: %.1f m, Ground speed: %.1f km/h", fps, groundLevel, avatar.position.y, avatar.position.y - groundLevel, speed))
    }
  }
}

private extension MTLRenderPassDescriptor {
  func setUpDepthAttachment(texture: MTLTexture) {
    depthAttachment.texture = texture
    depthAttachment.loadAction = .clear
    depthAttachment.storeAction = .store
    depthAttachment.clearDepth = 1
  }
  
  func setUpColorAttachment(position: Int, texture: MTLTexture) {
    let attachment: MTLRenderPassColorAttachmentDescriptor = colorAttachments[position]
    attachment.texture = texture
    attachment.loadAction = .clear
    attachment.storeAction = .store
    attachment.clearColor = MTLClearColorMake(0, 0, 0, 0)
  }
}
