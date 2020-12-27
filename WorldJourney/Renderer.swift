import Metal
import MetalKit
import ModelIO

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

  static var terrain = makePlanet(key: "spot")

  var wireframe = false
  var renderMode = RenderMode.realistic
  var renderObjects = false
  var screenScaleFactor: CGFloat = 1

  var frameCounter = 0
  var timeScale: Float = 1.0
  var lastGPUEndTime: CFTimeInterval = 0
  var lastPosition = simd_float2(0, 0)
  var sunPosition = simd_float3()
  let planet = PlanetPhysicsBody(mass: terrain.mass)
  let avatar = AvatarPhysicsBody(mass: 1e2)
  lazy var bodySystem = BodySystem(planet: planet, avatar: avatar)

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
    environs = Environs(device: device, library: library)
    skybox = Skybox(device: device, library: library, metalView: view, textureName: "space-sky")
    staticTexture = makeTexture(imageName: "noise", device: device)
    super.init()
    view.clearColor = MTLClearColor(red: 0.0/255.0, green: 0.0/255.0, blue: 0.0/255.0, alpha: 1.0)
    view.delegate = self
    mtkView(view, drawableSizeWillChange: view.bounds.size)
    avatar.position = SIMD3<Float>(0, 0, -Renderer.terrain.sphereRadius * 3)
    loadObjects(library: library)
    buildDepthStencilState(device: device)
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
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
    vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)

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

  private static func makeView(device: MTLDevice) -> MTKView {
    let metalView = GameView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
    metalView.device = device
    metalView.preferredFramesPerSecond = 60
    metalView.colorPixelFormat = .bgra8Unorm
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.framebufferOnly = true
    return metalView
  }

  private func makeViewMatrix(avatar: AvatarPhysicsBody) -> float4x4 {
    let p = avatar.position + normalize(avatar.position) * avatar.height
    return look(direction: avatar.look, eye: p, up: avatar.up)
  }

  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    let fov = Float.pi / 4
    return float4x4(perspectiveProjectionFov: fov, aspectRatio: aspectRatio, nearZ: Float(NEAR_CLIP), farZ: Renderer.terrain.sphereRadius * 100)
  }
  
  private func updateBodies() {
    
    let shift = Keyboard.IsKeyPressed(.shift)
    bodySystem.scale = shift ? Renderer.terrain.sphereRadius / 20 : 1
    
    // Craft control.

    // Descent booster.
    if Keyboard.IsKeyPressed(KeyCodes.space) {
      bodySystem.boost()
    }
    // Translation.
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
    // Attitude.
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

    // Diagnostic.
    
    if Keyboard.IsKeyPressed(KeyCodes.upArrow) {
      bodySystem.strafeAway()
    }
    if Keyboard.IsKeyPressed(KeyCodes.downArrow) {
      bodySystem.strafeTowards()
    }
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      bodySystem.boost()
    }
    if Keyboard.IsKeyPressed(KeyCodes.q) {
      bodySystem.fall()
    }
    if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
      bodySystem.halt()
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
    if Keyboard.IsKeyPressed(KeyCodes.q) {
      Self.terrain = makePlanet(key: UInt64.random(in: 0...UInt64.max))
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
      cameraPosition: avatar.position,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      sunPosition: sunPosition,
      sunColour: SIMD3<Float>(1.5, 1.5, 1.2),
      ambientColour: SIMD3<Float>(0.001, 0.001, 0.001),
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
    sunPosition = normalize(simd_float3(cos(lp), 0, -sin(lp))) * Renderer.terrain.sphereRadius * 1000
    
    let viewMatrix = makeViewMatrix(avatar: avatar)
    let projectionMatrix = makeProjectionMatrix()
    
    var uniforms = makeUniforms(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
    
    // Tessellation pass.
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    tessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: uniforms)
    computeEncoder.endEncoding()

    // GBuffer pass.
    let gBufferEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: gBuffer.gBufferRenderPassDescriptor)!
    gBuffer.renderGBufferPass(renderEncoder: gBufferEncoder, uniforms: uniforms, tessellator: tessellator, compositor: compositor, wireframe: wireframe)

    // Object pass.
    if renderObjects {
      gBufferEncoder.setRenderPipelineState(objectPipelineState)
      gBufferEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
      gBufferEncoder.setCullMode(.back)
      gBufferEncoder.setFrontFacing(.counterClockwise)
      gBufferEncoder.setDepthStencilState(depthStencilState)

      for mesh in objectMeshes {
        let vertexBuffer = mesh.vertexBuffers.first!
        gBufferEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
        gBufferEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        gBufferEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        for submesh in mesh.submeshes {
          let indexBuffer = submesh.indexBuffer
          gBufferEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                              indexCount: submesh.indexCount,
                                              indexType: submesh.indexType,
                                              indexBuffer: indexBuffer.buffer,
                                              indexBufferOffset: indexBuffer.offset,
                                              instanceCount: 2)
        }
      }
    }
    gBufferEncoder.endEncoding()
    
    // Composition pass.
    let compositionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    skybox.render(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositor.renderCompositionPass(renderEncoder: compositionEncoder, uniforms: uniforms)
    compositionEncoder.endEncoding()

    commandBuffer.present(drawable)
    
    updateBodies()

    var groundLevel: Float = 0
    let groundLevelBuffer = device.makeBuffer(bytes: &groundLevel, length: MemoryLayout<Float>.stride, options: [])!
    var normal = simd_float3(repeating: 0)
    let normalBuffer = device.makeBuffer(bytes: &normal, length: MemoryLayout<simd_float3>.stride, options: [])!
    let p = avatar.position

    let heightEncoder = commandBuffer.makeComputeCommandEncoder()!
    environs.computeHeight(heightEncoder: heightEncoder, uniforms: uniforms, position: p, groundLevelBuffer: groundLevelBuffer, normalBuffer: normalBuffer)
    
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

    bodySystem.fix(groundLevel: groundLevel, normal: normal)
    
    if (frameCounter % 60 == 0) {
      let fps = 1.0 / timeDiff
      let surfaceDistance = length(positionDiff)
      let groundSpeed = Double(surfaceDistance) / timeDiff * 60 * 60 / 1000.0
      let distance = length(avatar.position)
      let altitude = distance - groundLevel
      print(String(format: "FPS: %.1f, (%.1f, %.1f, %.1f)m, distance: %.1f, groundLevel: %.1f, altitude: %.1fm, groundNormal: (%.1f, %.1f, %.1f), %.1f speed, %.1f km/h", fps, avatar.position.x, avatar.position.y, avatar.position.z, distance, groundLevel, altitude, normal.x, normal.y, normal.z, length(avatar.speed), groundSpeed))
    }
  }
}
