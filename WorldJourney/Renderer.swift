import Metal
import MetalKit

class GameView: MTKView {}

class Renderer: NSObject {
  
  let device: MTLDevice
  let view: MTKView
  let tessellationPipelineState: MTLComputePipelineState
  let heightPipelineState: MTLComputePipelineState
  let renderPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  let controlPointsBuffer: MTLBuffer
  let commandQueue: MTLCommandQueue
  var frameCounter = 0
  var surfaceDistance: Float = Float(TERRAIN_SIZE) * 1.5
  let wireframe = false
  
  let heightMap: MTLTexture
  let noiseMap: MTLTexture
  let rockTexture: MTLTexture
  let snowTexture: MTLTexture

  let avatar = AvatarPhysicsBody(mass: 1e2)
  lazy var bodySystem = BodySystem(avatar: avatar)

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
  static var terrain = Terrain(
    size: terrainSize,
    height: terrainSize / 10,
    tessellation: Int32(maxTessellation),
    fractal: Fractal(
      octaves: 3,
      frequency: Float(TERRAIN_SIZE) * 0.00001,
      amplitude: Float(TERRAIN_SIZE) * 0.4,
      lacunarity: 2,
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
    depthStencilState = Renderer.makeDepthStencilState(device: device)!
    controlPointsBuffer = Renderer.makeControlPointsBuffer(patches: patches, terrain: Renderer.terrain, device: device)
    commandQueue = device.makeCommandQueue()!
    heightMap = Renderer.makeTexture(imageName: "mountain", device: device)
    noiseMap = Renderer.makeTexture(imageName: "noise", device: device)
    rockTexture = Renderer.makeTexture(imageName: "rock", device: device)
    snowTexture = Renderer.makeTexture(imageName: "snow", device: device)
    super.init()
    view.delegate = self
    
    avatar.position = SIMD3<Float>(0, 0, 0)
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
    pipelineStateDescriptor.tessellationPartitionMode = .fractionalEven

    return try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
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
    return try! textureLoader.newTexture(name: imageName, scaleFactor: 1.0, bundle: Bundle.main, options: nil)
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
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  
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
    
    var uniforms = Uniforms(
      cameraPosition: avatar.position,
      modelMatrix: modelMatrix,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      mvpMatrix: projectionMatrix * viewMatrix * modelMatrix
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
    
    
    // Render pass.

    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    renderEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
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

    
    // Draw.
    
    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: patchCount,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1,
                              baseInstance: 0)
    
    renderEncoder.endEncoding()

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
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    let nsData = NSData(bytesNoCopy: groundLevelBuffer.contents(),
                        length: groundLevelBuffer.length,
                        freeWhenDone: false)
    nsData.getBytes(&groundLevel, length: groundLevelBuffer.length)

    bodySystem.fix(groundLevel: groundLevel+2)
  }
}
