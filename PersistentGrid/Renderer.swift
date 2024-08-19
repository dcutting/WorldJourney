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

  let device = MTLCreateSystemDefaultDevice()!
  lazy var commandQueue = device.makeCommandQueue()!
  let view: MTKView

  var hasOcean = false
  var wireframe = false
  var renderMode = RenderMode.realistic
  var screenScaleFactor: CGFloat = 1
  var fov: Float
  var sunPosition = simd_float3()
  var skyModelTransform = matrix_float4x4.identity
  
  var fps: Double = 0
  var frameCounter = 0
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition: simd_float3!
  
  let terrainTessellator: Tessellator
  let oceanTessellator: Tessellator
  let gBuffer: GBuffer
  let rocks: Objects
  let compositor: Compositor
  let overlay: Overlay
  let environs: Environs
  let skybox: Skybox
  let physics: Physics

  var depthStencilState: MTLDepthStencilState!
  
  var game: Solar

  override init() {
    view = Renderer.makeView(device: device)
    let library = device.makeDefaultLibrary()!
    terrainTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(TERRAIN_PATCH_SIDE))
    oceanTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(OCEAN_PATCH_SIDE))
    gBuffer = GBuffer(device: device, library: library, maxTessellation: Int(MAX_TESSELLATION))
    rocks = Self.makeRocks(device: device, library: library)
    compositor = Compositor(device: device, library: library, view: view)
    overlay = Overlay(device: device, library: library, view: view)
    environs = Environs(device: device, library: library, patchesPerSide: Int(ENVIRONS_SIDE))
    skybox = Skybox(device: device, library: library, metalView: view, textureName: "space-sky")
    physics = Physics()
    fov = Self.calculateFieldOfView(degrees: 48)
    game = Solar.makeGame()
    super.init()
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 0.0/255.0, blue: 0.0/255.0, alpha: 1.0)
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size) // TODO: seems low-res until window size changes
    buildDepthStencilState(device: device)
    // TODO: yuck.
    newGame()
    DispatchQueue.main.asyncAfter(deadline: .now()) { self.newGame() }
  }
  
  private static func makeRocks(device: MTLDevice, library: MTLLibrary) -> Objects {
    guard let rockURL = Bundle.main.url(forResource: "low_poly_stone", withExtension: "usdz") else {
      fatalError("Could not find model file in app bundle")
    }
    let rockConfig = SurfaceObjectConfiguration(modelURL: rockURL, numInstances: 50, instanceRange: 200, viewDistance: 200, scale: 0.3...0.4, correction: matrix_float4x4(rotationAbout: SIMD3<Float>(-1, 0, 0), by: Float.pi/2))
    return Objects(device: device, library: library, config: rockConfig)
  }
  
  func buildDepthStencilState(device: MTLDevice) {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    depthStencilState = device.makeDepthStencilState(descriptor: descriptor)
  }
  
  func newGame() {
    game = Solar.makeGame()
    game.start(time: lastGPUEndTime)

    frameCounter = 0
    Self.terrain = game.config.terrain
    // set planet mass
//    let b = Renderer.terrain.sphereRadius + Renderer.terrain.fractal.amplitude + 100.0;
    physics.avatar.position = SIMD3<Float>(0, 0, -game.config.terrain.sphereRadius * 2).phyVector3
  }

  private static func makeView(device: MTLDevice) -> MTKView {
    let metalView = GameView(frame: NSRect(x: 0.0, y: 0.0, width: 1440.0, height: 900.0))
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
    let aspectRatio: Double = Double(view.bounds.width) / Double(view.bounds.height)
    let matrix = matrix_double4x4(perspectiveProjectionFov: Double(fov), aspectRatio: aspectRatio, nearZ: 0.5, farZ: Double(Renderer.terrain.sphereRadius * 8))
    return float4x4(matrix)
  }
  
  private static func calculateFieldOfView(monitorHeight: Float, monitorDistance: Float) -> Float {
    // https://steamcommunity.com/sharedfiles/filedetails/?l=german&id=287241027
    2 * (atan(monitorHeight / (monitorDistance * 2)))
  }
  
  private static func calculateFieldOfView(degrees: Float) -> Float {
    // https://andyf.me/fovcalc.html
    return degrees / 360.0 * 2 * Float.pi
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
    
    if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
      physics.halt()
    }
    if Keyboard.IsKeyPressed(KeyCodes.f) {
      wireframe = true
    }
    if Keyboard.IsKeyPressed(KeyCodes.g) {
      wireframe = false
    }
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      renderMode = .flatness
    }
    if Keyboard.IsKeyPressed(KeyCodes.n) {
      renderMode = .normals
    }
    if Keyboard.IsKeyPressed(KeyCodes.m) {
      renderMode = .realistic
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      adjustFractal(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      adjustFractal(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.z) {
      adjustWater(-1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
      adjustWater(1)
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
    rocks.albedoTexture = gBuffer.albedoTexture
    rocks.normalTexture = gBuffer.normalTexture
    rocks.positionTexture = gBuffer.positionTexture
    rocks.depthTexture = gBuffer.depthTexture
    rocks.buildRenderPassDescriptor()
    compositor.albedoTexture = gBuffer.albedoTexture
    compositor.normalTexture = gBuffer.normalTexture
    compositor.positionTexture = gBuffer.positionTexture
    compositor.waveNormalTexture = gBuffer.waveNormalTexture
    compositor.wavePositionTexture = gBuffer.wavePositionTexture
    overlay.update(device: device, size: size)
    compositor.renderPass.updateTextures(device: device, size: size)
  }
  
  func makeUniforms(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) -> Uniforms {
    Uniforms(
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
  }
  
  private func updateSun() {
    skyModelTransform = matrix_float4x4(rotationAbout: SIMD3<Float>(-1, 0, 0), by: Float(frameCounter) / 3000)
    sunPosition = (skyModelTransform * SIMD4<Float>(Renderer.terrain.sphereRadius * 500, Renderer.terrain.sphereRadius * 500, -Renderer.terrain.sphereRadius * 5000, 1)).xyz;
  }
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer() // TODO: use multiple command buffers to better parallelise the operations below?
      else { return }
    
    frameCounter += 1
    
    updateSun()

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
//    rocks.render(device: device, commandBuffer: commandBuffer, uniforms: uniforms, terrain: Renderer.terrain, depthStencilState: depthStencilState, wireframe: wireframe)

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
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositor.renderPass.descriptor)!
    skybox.render(renderEncoder: compositionEncoder, uniforms: uniforms, modelTransform: skyModelTransform)
    compositor.renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositionEncoder.endEncoding()

    // Overlay pass.
    overlay.fpsText = String(format: "%.2f", fps)
    overlay.energyText = game.energyText
    overlay.energyColour = game.energyColour
    overlay.worldTexture = compositor.renderPass.texture
    overlay.renderOverlayPass(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
    
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
    
    let world = World(sunPosition: sunPosition, physics: physics, terrain: Renderer.terrain)
    game.step(time: lastGPUEndTime, world: world)

    let waterLevel = hasOcean ? Renderer.terrain.sphereRadius + Renderer.terrain.waterLevel : 0
    physics.updatePlanet(mesh: groundMesh, waterLevel: waterLevel)
    physics.step(time: self.lastGPUEndTime)
        
    if (frameCounter % 60 == 0) {
      fps = 1.0 / timeDiff
      let distance = length(physics.avatar.position.simd)
      let metresPerSecond = length(physics.avatar.linearVelocity.simd)
      let kilometresPerHour: Float = metresPerSecond / 1000 * 60 * 60
      let altitude = length(physics.avatar.position.simd - groundCenter.simd)
      print(String(format: "FPS: %.1f, distance: %.1f, %.1f km/h, altitude: %.1f, isFlying?: %@ engine: %.1f, brake: %.1f, steering: %0.3f", fps, distance, kilometresPerHour, altitude, physics.isFlying ? "YES" : "no", physics.engineForce, physics.brakeForce, physics.steering))
    }
  }
}
