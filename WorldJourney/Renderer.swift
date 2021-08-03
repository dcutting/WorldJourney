import Metal
import MetalKit
import PhyKit

enum RenderMode: Int {
  case realistic = 0
  case normals = 1
  case flatness = 2
}

class GameView: MTKView {}

class Renderer: NSObject {

  static var terrain: Terrain!

  var hasOcean = false
  var wireframe = false
  var renderMode = RenderMode.realistic
  var renderGroundMesh = false
  var screenScaleFactor: CGFloat = 1

  var frameCounter = 0
  var timeScale: Float = 1.0
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition: simd_float3!
  var sunPosition = simd_float3()
  
  var physics: Physics!

  let device = MTLCreateSystemDefaultDevice()!
  lazy var commandQueue = device.makeCommandQueue()!
  let view: MTKView

  let terrainTessellator: Tessellator
  let oceanTessellator: Tessellator
  let gBuffer: GBuffer
  let smallRocks: Objects
  let largeRocks: Objects
  let compositor: Compositor
  let environs: Environs
  let skybox: Skybox
  
  var depthStencilState: MTLDepthStencilState!

  override init() {
    view = Renderer.makeView(device: device)
    let library = device.makeDefaultLibrary()!
    terrainTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(TERRAIN_PATCH_SIDE))
    oceanTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(OCEAN_PATCH_SIDE))
    gBuffer = GBuffer(device: device, library: library, maxTessellation: Int(MAX_TESSELLATION))
    
    guard let smallRockURL = Bundle.main.url(forResource: "A_Simple_Rock", withExtension: "usdz") else {
      fatalError("Could not find model file in app bundle")
    }
    let smallRockConfig = SurfaceObjectConfiguration(modelURL: smallRockURL, numInstances: 300, instanceRange: 100, scale: 0.4...0.75)
    smallRocks = Objects(device: device, library: library, config: smallRockConfig)
    
    guard let largeRockURL = Bundle.main.url(forResource: "Rock_Stone_02", withExtension: "usdz") else {
      fatalError("Could not find model file in app bundle")
    }
    let largeRockConfig = SurfaceObjectConfiguration(modelURL: largeRockURL, numInstances: 10, instanceRange: 500, scale: 5...10)
    largeRocks = Objects(device: device, library: library, config: largeRockConfig)
    
    compositor = Compositor(device: device, library: library, view: view)
    environs = Environs(device: device, library: library, patchesPerSide: Int(ENVIRONS_SIDE))
    skybox = Skybox(device: device, library: library, metalView: view, textureName: "space-sky")
    physics = Physics()
    super.init()
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 0.0/255.0, blue: 0.0/255.0, alpha: 1.0)
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size) // TODO: seems low-res until window size changes
    buildDepthStencilState(device: device)
    newGame()
  }
  
  func buildDepthStencilState(device: MTLDevice) {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    depthStencilState = device.makeDepthStencilState(descriptor: descriptor)
  }
  
  func newGame() {
    frameCounter = 0
    Self.terrain = makeRandomPlanet()
    // set planet mass
    // set random avatar speed/tumble
//    let initialTumbleMax: Float = 0.01
//    let initialTumbleRange: ClosedRange<Float> = -initialTumbleMax...initialTumbleMax
//    let initialSpeedMax: Float = 2
//    let initialSpeedRange: ClosedRange<Float> = -initialSpeedMax...initialSpeedMax
    physics.avatar.position = SIMD3<Float>(0, Renderer.terrain.sphereRadius * Float.random(in: 2...10), 0).phyVector3
  }

  func newDebugGame() {
    frameCounter = 0
    Self.terrain = enceladus
    // set planet mass
    physics.avatar.position = SIMD3<Float>(0, Renderer.terrain.sphereRadius + Renderer.terrain.fractal.amplitude + 100.0, 0).phyVector3
  }

  private static func makeView(device: MTLDevice) -> MTKView {
    let metalView = GameView(frame: NSRect(x: 0.0, y: 0.0, width: 1400.0, height: 900.0))
    metalView.device = device
    metalView.preferredFramesPerSecond = 60
    metalView.colorPixelFormat = .bgra8Unorm
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.framebufferOnly = true
    return metalView
  }

  private func makeViewMatrix() -> float4x4 {
    physics.avatar.transform.simd.inverse
  }

  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    let fov = Float.pi / (4)// - avatar.drawn * 1)
    return float4x4(perspectiveProjectionFov: fov, aspectRatio: aspectRatio, nearZ: 0.5, farZ: Renderer.terrain.sphereRadius * 100)
  }
  
  private func updateBodies(groundCenter: PHYVector3) {
    
    physics.setGroundCenter(groundCenter)
    
    // Craft control.

    // Translation.
    if Keyboard.IsKeyPressed(KeyCodes.w) {
      physics.forward()
    }
    if Keyboard.IsKeyPressed(KeyCodes.s) {
      physics.back()
    }
    if Keyboard.IsKeyPressed(KeyCodes.a) {
      physics.strafeLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.d) {
      physics.strafeRight()
    }
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      physics.strafeUp()
    }
    if Keyboard.IsKeyPressed(KeyCodes.q) {
      physics.strafeDown()
    }
    // Attitude.
    if Keyboard.IsKeyPressed(KeyCodes.j) {
      physics.turnLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.l) {
      physics.turnRight()
    }
    if Keyboard.IsKeyPressed(KeyCodes.i) {
      physics.turnDown()
    }
    if Keyboard.IsKeyPressed(KeyCodes.k) {
      physics.turnUp()
    }
    if Keyboard.IsKeyPressed(KeyCodes.u) {
      physics.rollLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.o) {
      physics.rollRight()
    }
    // Boost.
    if Keyboard.IsKeyPressed(KeyCodes.space) {
      physics.strafeUp()
    }

    // Diagnostic.
    
    if Keyboard.IsKeyPressed(KeyCodes.escape) {
      physics.halt()
      physics.avatar.position = SIMD3<Float>(0, Renderer.terrain.sphereRadius + 40, Renderer.terrain.sphereRadius).phyVector3
    }
    if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
      physics.halt()
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
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      renderMode = .flatness
    }
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      adjustFractal(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      adjustFractal(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
      adjustWater(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.z) {
      adjustWater(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.one) {
      screenScaleFactor = 1
      mtkView(view, drawableSizeWillChange: view.bounds.size)
    }
    if Keyboard.IsKeyPressed(KeyCodes.two) {
      screenScaleFactor = 2
      mtkView(view, drawableSizeWillChange: view.bounds.size)
    }
    if Keyboard.IsKeyPressed(KeyCodes.three) {
      screenScaleFactor = 4
      mtkView(view, drawableSizeWillChange: view.bounds.size)
    }
    if Keyboard.IsKeyPressed(KeyCodes.four) {
      screenScaleFactor = 8
      mtkView(view, drawableSizeWillChange: view.bounds.size)
    }
  }
  
  static var fractalOctavesX10 = Renderer.terrain.fractal.octaves
  
  func adjustFractal(_ f: Int) {
    Renderer.fractalOctavesX10 += Int32(f)
    Renderer.terrain.fractal.octaves = Int32(Renderer.fractalOctavesX10 / 10)
  }
  
  func adjustWater(_ f: Float) {
    Renderer.terrain.waterLevel += f
  }
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let newSize = CGSize(width: size.width / screenScaleFactor, height: size.height / screenScaleFactor)
    gBuffer.makeRenderPassDescriptors(device: device, size: newSize)
    smallRocks.albedoTexture = gBuffer.albedoTexture
    smallRocks.normalTexture = gBuffer.normalTexture
    smallRocks.positionTexture = gBuffer.positionTexture
    smallRocks.depthTexture = gBuffer.depthTexture
    smallRocks.buildRenderPassDescriptor()
    largeRocks.albedoTexture = gBuffer.albedoTexture
    largeRocks.normalTexture = gBuffer.normalTexture
    largeRocks.positionTexture = gBuffer.positionTexture
    largeRocks.depthTexture = gBuffer.depthTexture
    largeRocks.buildRenderPassDescriptor()
    compositor.albedoTexture = gBuffer.albedoTexture
    compositor.normalTexture = gBuffer.normalTexture
    compositor.positionTexture = gBuffer.positionTexture
    compositor.waveNormalTexture = gBuffer.waveNormalTexture
    compositor.wavePositionTexture = gBuffer.wavePositionTexture
  }
  
  func makeUniforms(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) -> Uniforms {
    let uniforms = Uniforms(
      screenWidth: Float(view.bounds.width),
      screenHeight: Float(view.bounds.height),
      cameraPosition: physics.avatar.position.simd,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      sunPosition: sunPosition,
      sunColour: SIMD3<Float>(1.5, 1.5, 1.2),
      ambientColour: SIMD3<Float>(0.005, 0.0052, 0.005),
      renderMode: Int32(renderMode.rawValue),
      time: Float(frameCounter)
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
    let sunDistance = Renderer.terrain.sphereRadius * 1000
    let sunPath = Float(frameCounter) / 3000
    let sunX = cos(sunPath) * sunDistance
    let sunY = sin(sunPath) * sunDistance
    sunPosition = simd_float3(sunX, sunY, 0)

    let viewMatrix = makeViewMatrix()
    let projectionMatrix = makeProjectionMatrix()
    
    let uniforms = makeUniforms(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
    
    // Tessellation pass.
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    let tessUniforms = uniforms
    terrainTessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: tessUniforms)
    if hasOcean {
      oceanTessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: tessUniforms)
    }
    computeEncoder.endEncoding()

    let p = normalize(physics.avatar.position.simd) * (Self.terrain.sphereRadius + 1)
    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    environs.computeHeight(heightEncoder: heightEncoder, position: p)
    heightEncoder.endEncoding()
    let (groundMesh, groundCenter) = environs.makeGroundMesh()

    // Terrain pass.
    let terrainEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBuffer.terrainRenderPassDescriptor)!
    gBuffer.renderTerrainPass(renderEncoder: terrainEncoder, uniforms: tessUniforms, tessellator: terrainTessellator, compositor: compositor, wireframe: wireframe)
    terrainEncoder.endEncoding()

    // Object pass.
    smallRocks.render(device: device, commandBuffer: commandBuffer, uniforms: uniforms, depthStencilState: depthStencilState)
    largeRocks.render(device: device, commandBuffer: commandBuffer, uniforms: uniforms, depthStencilState: depthStencilState)

    // Ocean pass.
    if hasOcean {
      let oceanEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBuffer.oceanRenderPassDescriptor)!
      gBuffer.renderOceanPass(renderEncoder: oceanEncoder, uniforms: tessUniforms, tessellator: oceanTessellator, compositor: compositor, wireframe: wireframe)
      oceanEncoder.endEncoding()
    }
    
//    if wireframe {
//      //    let environsEncoder = terrainEncoder
//      //
//      environsEncoder.setRenderPipelineState(objectPipelineState)
//      environsEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
//      environsEncoder.setCullMode(wireframe ? .none : .back)
//      environsEncoder.setFrontFacing(.counterClockwise)
//      environsEncoder.setDepthStencilState(depthStencilState)
//
//      let renderableGroundMesh = groundMesh.flatMap { $0 }.map { $0.simd }
//      let size = renderableGroundMesh.count * MemoryLayout<simd_float3>.size
//      let groundMeshBuffer = device.makeBuffer(bytes: renderableGroundMesh, length: size, options: .storageModeShared)!
//
//      environsEncoder.setVertexBuffer(groundMeshBuffer, offset: 0, index: 0)
//      environsEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      environsEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
//
//      environsEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: renderableGroundMesh.count)
//    }
//
//    environsEncoder.endEncoding()
    
    // Composition pass.
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    skybox.render(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositor.renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositionEncoder.endEncoding()

    commandBuffer.present(drawable)
    
    updateBodies(groundCenter: groundCenter)
    
    var timeDiff: CFTimeInterval = 0
    self.lastPosition = self.lastPosition ?? simd_float3(99999, 99999, 99999)
    commandBuffer.addCompletedHandler { buffer in
      let end = buffer.gpuEndTime
      timeDiff = end - self.lastGPUEndTime
      self.lastGPUEndTime = end
    }
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    self.lastPosition = physics.avatar.position.simd
    let waterLevel = hasOcean ? Renderer.terrain.sphereRadius + Renderer.terrain.waterLevel : 0
    physics.updatePlanet(mesh: groundMesh, waterLevel: waterLevel)
    physics.step(time: self.lastGPUEndTime)
        
    if (frameCounter % 60 == 0) {
      let fps = 1.0 / timeDiff
      let distance = length(physics.avatar.position.simd)
      let metresPerSecond = length(physics.avatar.linearVelocity.simd)
      let kilometresPerHour: Float = metresPerSecond / 1000 * 60 * 60
      let altitude = length(physics.avatar.position.simd - groundCenter.simd)
      print(String(format: "FPS: %.1f, distance: %.1f, %.1f km/h, altitude: %.1f, isFlying?: %@ engine: %.1f, brake: %.1f, steering: %0.3f", fps, distance, kilometresPerHour, altitude, physics.isFlying ? "YES" : "no", physics.engineForce, physics.brakeForce, physics.steering))
    }
  }
}
