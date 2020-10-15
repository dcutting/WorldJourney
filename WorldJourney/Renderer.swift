import Metal
import MetalKit
import ModelIO

enum RenderMode: Int {
  case realistic, normals
}

class GameView: MTKView {}

class Renderer: NSObject {

  static var moonA = Terrain(
    fractal: Fractal(
      octaves: 3,
      frequency: 0.01,
      amplitude: 50,
      lacunarity: 2.1,
      persistence: 0.4,
      warpFrequency: 0.004,
      warpAmplitude: 4,
      erode: 1
    ),
    waterLevel: -1700,
    snowLevel: 30,
    sphereRadius: 500,
    groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
    skyColour: SIMD3<Float>(0, 0, 0) //SIMD3<Float>(0xE3/255.0, 0x9E/255.0, 0x50/255.0)
  )
  
  static var enceladus = Terrain(
    fractal: Fractal(
      octaves: 4,
      frequency: 0.01,
      amplitude: 40,
      lacunarity: 2.1,
      persistence: 0.4,
      warpFrequency: 0,
      warpAmplitude: 0,
      erode: 1
    ),
    waterLevel: -1700,
    snowLevel: 20,
    sphereRadius: 500,
    groundColour: SIMD3<Float>(0x1A/255.0, 0x30/255.0, 0x30/255.0),
    skyColour: SIMD3<Float>(0, 0, 0) //SIMD3<Float>(0xE3/255.0, 0x9E/255.0, 0x50/255.0)
  )
  
  static var terrain = enceladus

  var frameCounter = 0
  var wireframe = false
  var renderMode = RenderMode.realistic
  var timeScale: Float = 1.0
  var groundLevelReadings = [Float](repeating: 0, count: 1)

  let device: MTLDevice
  let view: MTKView
  let tessellator: Tessellator
  let compositor: Compositor
  let heightPipelineState: MTLComputePipelineState
  let gBufferPipelineState: MTLRenderPipelineState
  var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
  let commandQueue: MTLCommandQueue
   
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition = simd_float2(0, 0)
  
  var sunPosition = simd_float3()
  
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!

  let normalMapTexture: MTLTexture

  let avatar = AvatarPhysicsBody(mass: 1e2)
  lazy var bodySystem = BodySystem(avatar: avatar)

  override init() {
    device = Renderer.makeDevice()
    view = Renderer.makeView(device: device)
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 0.0/255.0, blue: 0.0/255.0, alpha: 1.0)
    let library = device.makeDefaultLibrary()!
    tessellator = Tessellator(device: device, library: library, patchesPerSide: Int(PATCH_SIDE))
    heightPipelineState = Renderer.makeHeightPipelineState(device: device, library: library)
    gBufferPipelineState = Renderer.makeGBufferPipelineState(device: device, library: library, metalView: view)
    compositor = Compositor(device: device, library: library, view: view)
    commandQueue = device.makeCommandQueue()!
    normalMapTexture = Renderer.makeTexture(imageName: "snow_normal", device: device)
    super.init()
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size)
//    avatar.position = SIMD3<Float>(0, 0, -Renderer.terrain.sphereRadius + Renderer.terrain.fractal.amplitude * 2)
    avatar.position = SIMD3<Float>(0, 0, -Renderer.terrain.sphereRadius * 4)
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

  private static func makeTexture(imageName: String, device: MTLDevice) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    return try! textureLoader.newTexture(name: imageName, scaleFactor: 1.0, bundle: Bundle.main, options: [.textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))])
  }

  private static func makeHeightPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "height_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Height kernel function not found.") }
    return state
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
    descriptor.maxTessellationFactor = Int(MAX_TESSELLATION)
    descriptor.tessellationPartitionMode = .fractionalEven

    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  private func makeViewMatrix(avatar: AvatarPhysicsBody) -> float4x4 {
    let p = avatar.position + normalize(avatar.position) * avatar.height
    return look(direction: avatar.look, eye: p, up: avatar.up)
  }

  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    let fov = Float.pi / 4
    return float4x4(perspectiveProjectionFov: fov, aspectRatio: aspectRatio, nearZ: 1, farZ: Renderer.terrain.sphereRadius * 10)
  }
  
  private func updateBodies() {
    
    let shift = Keyboard.IsKeyPressed(.shift)
    bodySystem.scale = shift ? Renderer.terrain.sphereRadius / 20 : 1
    
    if Keyboard.IsKeyPressed(KeyCodes.upArrow) {
      bodySystem.strafeAway()
    }
    if Keyboard.IsKeyPressed(KeyCodes.downArrow) {
      bodySystem.strafeTowards()
    }
    if Keyboard.IsKeyPressed(KeyCodes.w) {
      bodySystem.forward()
    }
    if Keyboard.IsKeyPressed(KeyCodes.s) {
      bodySystem.back()
    }
    if Keyboard.IsKeyPressed(KeyCodes.a) {
      bodySystem.strafeLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.d) {
      bodySystem.strafeRight()
    }
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      bodySystem.boost()
    }
//    if Keyboard.IsKeyPressed(KeyCodes.space) {
//      bodySystem.airBrake()
//    }
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
    if Keyboard.IsKeyPressed(KeyCodes.space) {
      bodySystem.stopRotation()
    }
    if Keyboard.IsKeyPressed(KeyCodes.zero) {
      timeScale *= 1.1
    }
    if Keyboard.IsKeyPressed(KeyCodes.nine) {
      timeScale /= 1.1
    }
    if Keyboard.IsKeyPressed(KeyCodes.f) {
      wireframe = true
    }
    if Keyboard.IsKeyPressed(KeyCodes.g) {
      wireframe = false
    }
    if Keyboard.IsKeyPressed(KeyCodes.n) {
      renderMode = .normals
    }
    if Keyboard.IsKeyPressed(KeyCodes.m) {
      renderMode = .realistic
    }
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      adjustFractal(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      adjustFractal(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.v) {
      adjustWater(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      adjustWater(-1)
    }
    bodySystem.update()
  }
  
  static var fractalOctavesX10 = Renderer.terrain.fractal.octaves
  
  func adjustFractal(_ f: Int) {
    Renderer.fractalOctavesX10 += Int32(f)
    Renderer.terrain.fractal.octaves = Int32(Renderer.fractalOctavesX10 / 10)
  }
  
  func adjustWater(_ f: Float) {
    Renderer.terrain.waterLevel += f
  }

  func renderGBufferPass(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
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

    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: tessellator.patchCount,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1,
                              baseInstance: 0)
    
    renderEncoder.endEncoding()

    renderEncoder.popDebugGroup()
  }
}
  
extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    gBufferRenderPassDescriptor = makeGBufferRenderPassDescriptor(device: device, size: size)
    compositor.albedoTexture = albedoTexture
    compositor.normalTexture = normalTexture
    compositor.positionTexture = positionTexture
  }
  
  func makeUniforms(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) -> Uniforms {
    let modelMatrix = matrix_float4x4(diagonal: SIMD4<Float>(repeating: 1.0))
    let lightDirection = -sunPosition
    let uniforms = Uniforms(
      scale: 1,
      theta: 0,
      screenWidth: Float(view.bounds.width),
      screenHeight: Float(view.bounds.height),
      cameraPosition: avatar.position,
      modelMatrix: modelMatrix,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      mvpMatrix: projectionMatrix * viewMatrix * modelMatrix,
      sunDirection: lightDirection,
      sunPosition: sunPosition,
      sunColour: SIMD3<Float>(repeating: 1.0),
      ambient: 0.15,
      renderMode: Int32(renderMode.rawValue)
    )
    return uniforms
  }
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer() // TODO: use multiple command buffers to better parallelise the operations below?
      else { return }
    
    frameCounter += 1
    let lp = timeScale * Float(frameCounter) / 1000.0
    sunPosition = normalize(simd_float3(cos(lp), 0, sin(lp))) * Renderer.terrain.sphereRadius * 100
    
    let viewMatrix = makeViewMatrix(avatar: avatar)
    let projectionMatrix = makeProjectionMatrix()
    
    var uniforms = makeUniforms(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
    // Tessellation pass.
    
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    tessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: uniforms)

    
    
    // GBuffer pass.
    let gBufferEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBufferRenderPassDescriptor)!
    renderGBufferPass(renderEncoder: gBufferEncoder, uniforms: uniforms)
    
    // Composition pass.
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    compositor.renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)

    commandBuffer.present(drawable)

    
    
    updateBodies()

    var groundLevel: Float = 0
    let groundLevelBuffer = device.makeBuffer(bytes: &groundLevel, length: MemoryLayout<Float>.stride, options: [])!
    var normal = simd_float3(repeating: 0)
    let normalBuffer = device.makeBuffer(bytes: &normal, length: MemoryLayout<simd_float3>.stride, options: [])!
    var p = avatar.position
    
    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    heightEncoder.setComputePipelineState(heightPipelineState)
    heightEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    heightEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    heightEncoder.setBytes(&p, length: MemoryLayout<SIMD3<Float>>.stride, index: 2)
    heightEncoder.setBuffer(groundLevelBuffer, offset: 0, index: 3)
    heightEncoder.setBuffer(normalBuffer, offset: 0, index: 4)
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
    
    let groundLevelData = NSData(bytesNoCopy: groundLevelBuffer.contents(),
                                 length: groundLevelBuffer.length,
                                 freeWhenDone: false)
    groundLevelData.getBytes(&groundLevel, length: groundLevelBuffer.length)

    let normalData = NSData(bytesNoCopy: normalBuffer.contents(),
                            length: normalBuffer.length,
                            freeWhenDone: false)
    normalData.getBytes(&normal, length: normalBuffer.length)

//    groundLevelReadings.append(groundLevel)
//    groundLevelReadings.removeFirst()
//    
//    groundLevel = groundLevelReadings.reduce(0) { a, x in a+x } / Float(groundLevelReadings.count)
    bodySystem.fix(groundLevel: groundLevel, normal: normal)
    
    if (frameCounter % 60 == 0) {
      let fps = 1.0 / timeDiff
      let surfaceDistance = length(positionDiff)
      let groundSpeed = Double(surfaceDistance) / timeDiff * 60 * 60 / 1000.0
      let distance = length(avatar.position)
      let altitude = distance - groundLevel
//    let sphereNormal = normalize(avatar.position)
//    let terrainNormal = normalize(normal)
//    print(String(format: "Terrain normal: %.3f, %.3f, %.3f", terrainNormal.x, terrainNormal.y, terrainNormal.z))
//    print(String(format: "Sphere:         %.3f, %.3f, %.3f", sphereNormal.x, sphereNormal.y, sphereNormal.z))
    print(String(format: "FPS: %.1f, (%.1f, %.1f, %.1f)m, distance: %.1f, groundLevel: %.1f, altitude: %.1fm, groundNormal: (%.1f, %.1f, %.1f), %.1f speed, %.1f km/h", fps, avatar.position.x, avatar.position.y, avatar.position.z, distance, groundLevel, altitude, normal.x, normal.y, normal.z, length(avatar.speed), groundSpeed))
    }
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
