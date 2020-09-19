import Metal
import MetalKit
import ModelIO

enum RenderMode: Int, CaseIterable {
  case realistic, normals, height
  
  mutating func cycle() {
    self = Self(rawValue: (self.rawValue + 1) % RenderMode.allCases.count)!
  }
}

class GameView: MTKView {}

class Renderer: NSObject {

  static var terrain = Terrain(
    tessellation: Int32(maxTessellation),
    fractal: Fractal(
      octaves: 4,
      frequency: 0.000001,
      amplitude: 2000,
      lacunarity: 2.1,
      persistence: 0.4
    ),
    waterLevel: -1700,
    snowLevel: 1900,
    sphereRadius: 50000
  )

  let device: MTLDevice
  let view: MTKView
  let tessellationPipelineState: MTLComputePipelineState
  let heightPipelineState: MTLComputePipelineState
  let gBufferPipelineState: MTLRenderPipelineState
  let compositionPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
  var controlPointsBuffer: MTLBuffer
  let commandQueue: MTLCommandQueue
  var frameCounter = 0
  var wireframe = true
  var renderMode = RenderMode.realistic
  var timeScale: Float = 1.0
  
  var groundLevelReadings = [Float](repeating: 0, count: 1)
 
  let backgroundQueue = DispatchQueue(label: "background")
  
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition = simd_float2(0, 0)
  
  var lightDirection = simd_float3(1, -0.2, 0)
  
  let heightMap: MTLTexture
  let noiseMap: MTLTexture
  let cliffNormalMap: MTLTexture
  let snowNormalMap: MTLTexture
  let rockTexture: MTLTexture
  let snowTexture: MTLTexture
  
  let skyModel: MDLSkyCubeTexture
  var skyTexture: MTLTexture

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
  
  let patches = Int(PATCH_SIDE)
  var patchCount: Int!
  
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

  override init() {
    device = Renderer.makeDevice()
    view = Renderer.makeView(device: device)
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 178.0/255.0, blue: 228.0/255.0, alpha: 1.0)
    let library = device.makeDefaultLibrary()!
    tessellationPipelineState = Renderer.makeComputePipelineState(device: device, library: library)
    heightPipelineState = Renderer.makeHeightPipelineState(device: device, library: library)
    gBufferPipelineState = Renderer.makeGBufferPipelineState(device: device, library: library, metalView: view)
    compositionPipelineState = Renderer.makeCompositionPipelineState(device: device, library: library, metalView: view)
    depthStencilState = Renderer.makeDepthStencilState(device: device)!
    (controlPointsBuffer, patchCount) = Renderer.makeControlPointsBuffer(patches: patches, terrain: Renderer.terrain, device: device)
    commandQueue = device.makeCommandQueue()!
    heightMap = Renderer.makeTexture(imageName: "mars", device: device)
    noiseMap = Renderer.makeTexture(imageName: "noise", device: device)
//    noiseMap = Renderer.makeNoise(device: device)
    cliffNormalMap = Renderer.makeTexture(imageName: "scratched", device: device)
    snowNormalMap = Renderer.makeTexture(imageName: "moon_normal", device: device)
    rockTexture = Renderer.makeTexture(imageName: "rock", device: device)
    snowTexture = Renderer.makeTexture(imageName: "snow", device: device)
    skyModel = Renderer.makeSkybox(device: device)
    skyTexture = Renderer.generateSkyTexture(device: device, skyModel: skyModel)
    super.init()
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size)
    quadVerticesBuffer = device.makeBuffer(bytes: quadVertices,
                                                    length: MemoryLayout<Float>.size * quadVertices.count, options: [])
    quadVerticesBuffer.label = "Quad vertices"
    quadTexCoordsBuffer = device.makeBuffer(bytes: quadTexCoords,
                                                     length: MemoryLayout<Float>.size * quadTexCoords.count, options: [])
    quadTexCoordsBuffer.label = "Quad texCoords"

    avatar.position = SIMD3<Float>(0, Float(Renderer.terrain.sphereRadius)+Float(Renderer.terrain.fractal.amplitude)*100, 0)
//    avatar.speed = SIMD3<Float>(0, 0, 300)
  }
  
  private static func makeNoise(device: MTLDevice) -> MTLTexture {
//    let mdlTexture = MDLNoiseTexture(scalarNoiseWithSmoothness: 0.9, name: "noise", textureDimensions: vector_int2(4096, 4096), channelCount: 1, channelEncoding: .float32, grayscale: true)
//    let mdlTexture = MDLNoiseTexture(vectorNoiseWithSmoothness: 1.0, name: "noise", textureDimensions: vector_int2(1024, 1024), channelEncoding: .float32)
    let mdlTexture = MDLNoiseTexture(cellularNoiseWithFrequency: 0.1, name: "noise", textureDimensions: vector_int2(1024, 1024), channelEncoding: .float32)
    let loader = MTKTextureLoader(device: device)
    return try! loader.newTexture(texture: mdlTexture, options: [
      .textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))
    ])
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
  
  private static func makeSkybox(device: MTLDevice) -> MDLSkyCubeTexture {
    MDLSkyCubeTexture(name: "sky",
                      channelEncoding: .float32,
                      textureDimensions: vector_int2(256, 256),
                      turbidity: 0.5,
                      sunElevation: 0.75,
                      upperAtmosphereScattering: 0.5,
                      groundAlbedo: 0.5)
  }

  private static func generateSkyTexture(device: MTLDevice, skyModel: MDLSkyCubeTexture) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    return try! textureLoader.newTexture(texture: skyModel, options: nil)
  }

  private func updateSkyTexture() {
    skyModel.sunElevation += 0.02
    skyModel.update()
    skyTexture = Self.generateSkyTexture(device: device, skyModel: skyModel)
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
    descriptor.tessellationPartitionMode = .pow2

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
  
  private static func makeControlPointsBuffer(patches: Int, terrain: Terrain, device: MTLDevice) -> (MTLBuffer, Int) {
    let controlPoints = createControlPoints(patches: patches, size: 2.0)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!, controlPoints.count/4)
  }
  
  private static func makeTexture(imageName: String, device: MTLDevice) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    return try! textureLoader.newTexture(name: imageName, scaleFactor: 1.0, bundle: Bundle.main, options: [.textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))])
  }

  private func makeModelMatrix() -> float4x4 {
    let (scale, theta): (Float, Float) = calcTerrainScale()
    let d = scale / Float(PATCH_SIDE)
    let x = floor(avatar.position.x / d) * d
    let z = floor(avatar.position.z / d) * d
//    let x = avatar.position.x
//    let z = avatar.position.z
    let t = float4x4(translationBy: SIMD3<Float>(x, 0, z))
    let s = float4x4(scaleBy: scale)
    return t * s
  }
  
  private func makeViewMatrix(avatar: AvatarPhysicsBody) -> float4x4 {
    look(direction: avatar.look, eye: avatar.position, up: avatar.up)
  }

  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    let fov = Float.pi / 4
    return float4x4(perspectiveProjectionFov: fov, aspectRatio: aspectRatio, nearZ: 1, farZ: 1200000.0)
  }

  private func updateBodies() {
    
    let shift = Keyboard.IsKeyPressed(.shift)
    bodySystem.scale = shift ? 50 : 1
    
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
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      bodySystem.boost()
    }
    if Keyboard.IsKeyPressed(KeyCodes.space) {
      bodySystem.airBrake()
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
        bodySystem.strafeDown()
    }
    if Keyboard.IsKeyPressed(KeyCodes.c) {
        bodySystem.strafeUp()
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
    if Keyboard.IsKeyPressed(KeyCodes.p) {
      timeScale *= 1.1
    }
    if Keyboard.IsKeyPressed(KeyCodes.o) {
      timeScale /= 1.1
    }
    if Keyboard.IsKeyPressed(KeyCodes.f) {
      wireframe.toggle()
    }
    if Keyboard.IsKeyPressed(KeyCodes.n) {
      renderMode.cycle()
    }
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      adjustFractal(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      adjustFractal(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.h) {
      adjustWater(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.g) {
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

  func calcTerrainScale() -> (Float, Float) {
    let r = Double(Self.terrain.sphereRadius)
    let m = Double(Self.terrain.fractal.amplitude)
    let h = Double(avatar.position.y+avatar.height)
    let alpha = acos(r / (r+m))
    let beta = acos(r / (h))
    let theta = alpha + beta
    let horizonDistance = theta * r
    let expandedHorizonDistance = (horizonDistance)// / Double(PATCH_SIDE)) * Double(PATCH_SIDE + 4)
    var size = expandedHorizonDistance * 2  // TODO: this doesn't fix it - try 100km radius bodies
//    if h - r < 10000 {
//      size = pow(2.0, ceil(log2(size)))
//    }
    return (Float(size), Float(theta))
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
    renderEncoder.setVertexTexture(snowNormalMap, index: 2)
//    renderEncoder.setFragmentTexture(cliffNormalMap, index: 0)
    renderEncoder.setFragmentTexture(snowNormalMap, index: 1)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    renderEncoder.setFragmentBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)

    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: patchCount, //TODO: actual count is less when it's a circle
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
//    renderEncoder.setFragmentTexture(rockTexture, index: 3)
//    renderEncoder.setFragmentTexture(snowTexture, index: 4)

    renderEncoder.setFragmentTexture(heightMap, index: 5)
    renderEncoder.setFragmentTexture(noiseMap, index: 6)
//    renderEncoder.setFragmentTexture(cliffNormalMap, index: 7)
//    renderEncoder.setFragmentTexture(skyTexture, index: 8)

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
    
//    if frameCounter % 60 == 0 {
//      adjustTerrainSize()
//    }

    frameCounter += 1
    
    let commandBuffer = commandQueue.makeCommandBuffer()!

    let modelMatrix = makeModelMatrix()
    let viewMatrix = makeViewMatrix(avatar: avatar)
    let projectionMatrix = makeProjectionMatrix()
    
    let lp = timeScale * Float(frameCounter) / 1000.0
    lightDirection = simd_float3(cos(lp), -0.3, sin(lp))
//    if frameCounter % 60 == 0 {
//      backgroundQueue.async {
//        self.updateSkyTexture()
//      }
//    }
    let (scale, theta) = calcTerrainScale()
    
    var uniforms = Uniforms(
      scale: scale,
      theta: theta,
      screenWidth: Float(view.bounds.width),
      screenHeight: Float(view.bounds.height),
      cameraPosition: avatar.position,
      modelMatrix: modelMatrix,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      mvpMatrix: projectionMatrix * viewMatrix * modelMatrix,
      lightDirection: lightDirection,
      renderMode: Int32(renderMode.rawValue)
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
    
    // GBuffer pass.
    let gBufferEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBufferRenderPassDescriptor)!
    renderGBufferPass(renderEncoder: gBufferEncoder, uniforms: uniforms)
    
    // Composition pass.
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)

    commandBuffer.present(drawable)

    
    
    updateBodies()

    var groundLevel: Float = 0
    let groundLevelBuffer = device.makeBuffer(bytes: &groundLevel, length: MemoryLayout<Float>.stride, options: [])!
    var normal = simd_float3(repeating: 0)
    let normalBuffer = device.makeBuffer(bytes: &normal, length: MemoryLayout<simd_float3>.stride, options: [])!
    var xz = avatar.position.xz
    
    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    heightEncoder.setComputePipelineState(heightPipelineState)
    heightEncoder.setTexture(heightMap, index: 0)
    heightEncoder.setTexture(noiseMap, index: 1)
    heightEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    heightEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    heightEncoder.setBytes(&xz, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
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
    groundLevel += Renderer.terrain.sphereRadius

    let normalData = NSData(bytesNoCopy: normalBuffer.contents(),
                            length: normalBuffer.length,
                            freeWhenDone: false)
    normalData.getBytes(&normal, length: normalBuffer.length)

    groundLevelReadings.append(groundLevel)
    groundLevelReadings.removeFirst()
    
    groundLevel = groundLevelReadings.reduce(0) { a, x in a+x } / Float(groundLevelReadings.count)
    
    bodySystem.fix(groundLevel: groundLevel+avatar.height, normal: normal)

    
    if (frameCounter % 60 == 0) {
      let fps = 1.0 / timeDiff
      let distance = length(positionDiff)
      let speed = Double(distance) / timeDiff * 60 * 60 / 1000.0
      let (scale, theta) = calcTerrainScale()
      print(String(format: "FPS: %.1f, scale: %f (%f), (%.1f, %.1f, %.1f)m, %.1fm up, %.1f km/h", fps, scale, theta, avatar.position.x, avatar.position.y, avatar.position.z, avatar.position.y - groundLevel, speed))
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
