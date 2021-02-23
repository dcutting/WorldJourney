import Metal
import MetalKit
import ModelIO
import PhyKit

/* good planets:
 
 et tu brute
 lexie
 chicken
 I am the very model of a modern major general
 mars
 earth
 saturn (ground disappeared at one point!)
 
 */

enum RenderMode: Int {
  case realistic = 0
  case normals = 1
}

class GameView: MTKView {}

class Renderer: NSObject {

  static var terrain: Terrain!

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

  let tessellator: Tessellator
  let gBuffer: GBuffer
  let compositor: Compositor
  let environs: Environs
  let skybox: Skybox
  
  let staticTexture: MTLTexture!
  
  var objectPipelineState: MTLRenderPipelineState!
  var objectMeshes: [MTKMesh] = []
  var depthStencilState: MTLDepthStencilState!

  override init() {
    view = Renderer.makeView(device: device)
    let library = device.makeDefaultLibrary()!
    tessellator = Tessellator(device: device, library: library, patchesPerSide: Int(PATCH_SIDE))
    gBuffer = GBuffer(device: device, library: library, maxTessellation: Int(MAX_TESSELLATION))
    compositor = Compositor(device: device, library: library, view: view)
    environs = Environs(device: device, library: library, patchesPerSide: Int(ENVIRONS_SIDE))
    skybox = Skybox(device: device, library: library, metalView: view, textureName: "space-sky")
    staticTexture = makeTexture(imageName: "noise", device: device)
    physics = Physics()
    super.init()
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 0.0/255.0, blue: 0.0/255.0, alpha: 1.0)
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size) // TODO: seems low-res until window size changes
    loadObjects(library: library)
    buildDepthStencilState(device: device)
    newGame()
  }
  
  private func makeObjectDescriptors(device: MTLDevice, library: MTLLibrary) -> (MDLVertexDescriptor, MTLRenderPipelineState) {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[1].pixelFormat = .rgba16Float
    descriptor.colorAttachments[2].pixelFormat = .rgba32Float
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "Object state"
    
    descriptor.vertexFunction = library.makeFunction(name: "object_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "object_fragment")
    
    let vertexDescriptor = MDLVertexDescriptor()
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
//    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
//    vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<simd_float3>.size)

    descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

    let state = try! device.makeRenderPipelineState(descriptor: descriptor)
    
    return (vertexDescriptor, state)
  }
  
  private func loadObjects(library: MTLLibrary) {
    let (vertexDescriptor, state) = makeObjectDescriptors(device: device, library: library)
    objectPipelineState = state
    
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let modelURL = Bundle.main.url(forResource: "toy_biplane", withExtension: "usdz")!
    let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
    
    do {
        (_, objectMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
    } catch {
        fatalError("Could not extract meshes from Model I/O asset")
    }
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
    Self.terrain = choco
    // set planet mass
    physics.avatar.position = SIMD3<Float>(0, Renderer.terrain.sphereRadius + 1000, 0).phyVector3
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
    return float4x4(perspectiveProjectionFov: fov, aspectRatio: aspectRatio, nearZ: Float(NEAR_CLIP), farZ: Renderer.terrain.sphereRadius * 100)
  }
  
  private func updateBodies() {
    
    // Craft control.

    // Translation.
    if Keyboard.IsKeyPressed(KeyCodes.w) {
      physics.forward()
    }
    if Keyboard.IsKeyPressed(KeyCodes.s) {
      physics.back()
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
      physics.driveForward()
    }
    if Keyboard.IsKeyPressed(KeyCodes.c) {
      physics.driveBack()
    }
    if Keyboard.IsKeyPressed(KeyCodes.v) {
      physics.steerLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      physics.steerRight()
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
      physics.avatar.position = SIMD3<Float>(0, Renderer.terrain.sphereRadius + 200, Renderer.terrain.sphereRadius).phyVector3
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
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      adjustFractal(1)
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      adjustFractal(-1)
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
    gBuffer.makeGBufferRenderPassDescriptor(device: device, size: newSize)
    compositor.albedoTexture = gBuffer.albedoTexture
    compositor.normalTexture = gBuffer.normalTexture
    compositor.positionTexture = gBuffer.positionTexture
    compositor.staticTexture = staticTexture
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
//    let lp = timeScale * Float(frameCounter) / 100000.0
    sunPosition = simd_float3(0, 0, Renderer.terrain.sphereRadius * 1000)
//    sunPosition = normalize(simd_float3(cos(lp), 0, -sin(lp))) * Renderer.terrain.sphereRadius * 1000

    let viewMatrix = makeViewMatrix()
    let projectionMatrix = makeProjectionMatrix()
    
    var uniforms = makeUniforms(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
    
    // Tessellation pass.
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    var tessUniforms = uniforms
//    tessUniforms.cameraPosition = normalize(physics.avatar.position.simd) * (Self.terrain.sphereRadius + 1)
    tessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: tessUniforms)
    computeEncoder.endEncoding()

    let p = normalize(physics.avatar.position.simd) * (Self.terrain.sphereRadius + 1)
    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    environs.computeHeight(heightEncoder: heightEncoder, position: p)
    heightEncoder.endEncoding()
    let groundMesh = environs.makeGroundMesh()

    // GBuffer pass.
    let gBufferEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBuffer.gBufferRenderPassDescriptor)!
    gBuffer.renderGBufferPass(renderEncoder: gBufferEncoder, uniforms: tessUniforms, tessellator: tessellator, compositor: compositor, wireframe: wireframe)

    // Object pass.
    if wireframe {
      gBufferEncoder.setRenderPipelineState(objectPipelineState)
      gBufferEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
      gBufferEncoder.setCullMode(wireframe ? .none : .back)
      gBufferEncoder.setFrontFacing(.counterClockwise)
      gBufferEncoder.setDepthStencilState(depthStencilState)

//      for mesh in objectMeshes {
//        let vertexBuffer = mesh.vertexBuffers.first!
//        gBufferEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
//        gBufferEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//        gBufferEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
//
//        for submesh in mesh.submeshes {
//          let indexBuffer = submesh.indexBuffer
//          gBufferEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
//                                              indexCount: submesh.indexCount,
//                                              indexType: submesh.indexType,
//                                              indexBuffer: indexBuffer.buffer,
//                                              indexBufferOffset: indexBuffer.offset,
//                                              instanceCount: 2)
//        }
//      }
//      let count = patchCount * (4 + 2)  // 4 edges + 2 insides
      let renderableGroundMesh = groundMesh.flatMap { $0 }.map { $0.simd }
      let size = renderableGroundMesh.count * MemoryLayout<simd_float3>.size
      let groundMeshBuffer = device.makeBuffer(bytes: renderableGroundMesh, length: size, options: .storageModeShared)!

      gBufferEncoder.setVertexBuffer(groundMeshBuffer, offset: 0, index: 0)
      gBufferEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      gBufferEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
      
      gBufferEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: renderableGroundMesh.count)
    }
    gBufferEncoder.endEncoding()
    
    // Composition pass.
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    skybox.render(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositor.renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositionEncoder.endEncoding()

    commandBuffer.present(drawable)
    
    updateBodies()
    
    var timeDiff: CFTimeInterval = 0
    var positionDiff: Float = 0
    self.lastPosition = self.lastPosition ?? simd_float3(99999, 99999, 99999)
    commandBuffer.addCompletedHandler { buffer in
      let end = buffer.gpuEndTime
      timeDiff = end - self.lastGPUEndTime
      self.lastGPUEndTime = end
      positionDiff = distance(self.lastPosition, self.physics.avatar.position.simd)
    }
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
//    if positionDiff > 20 {
//      print("^^^ \(positionDiff)")
      self.lastPosition = physics.avatar.position.simd
      physics.updatePlanetGeometry(mesh: groundMesh)
//    }
    physics.step(time: self.lastGPUEndTime)
        
    if (frameCounter % 60 == 0) {
      let fps = 1.0 / timeDiff
      let distance = length(physics.avatar.position.simd)
      let metresPerSecond = length(physics.avatar.linearVelocity.simd)
      let kilometresPerHour: Float = metresPerSecond / 1000 * 60 * 60
      print(String(format: "FPS: %.1f, distance: %.1f, %.1f km/h, engine: %.1f, brake: %.1f, steering: %0.3f", fps, distance, kilometresPerHour, physics.engineForce, physics.brakeForce, physics.steering))
    }
  }
}
