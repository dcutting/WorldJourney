import Metal
import MetalKit

class Renderer: NSObject {
  
  let device: MTLDevice
  let view: MTKView
  let tessellationPipelineState: MTLComputePipelineState
  let renderPipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState
  let controlPointsBuffer: MTLBuffer
  let commandQueue: MTLCommandQueue
  var frameCounter = 0
  var surfaceDistance: Float = 50.0
  let wireframe = false
  
  let heightMap: MTLTexture
  let noiseMap: MTLTexture
  let rockTexture: MTLTexture

  var edgeFactors: [Float] = [4]
  var insideFactors: [Float] = [4]
  
  let patches = (horizontal: 32, vertical: 32)
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
  
  static var terrainSize: Float = 10
  static var terrain = Terrain(
    size: terrainSize,
    height: 1,
    frequency: 0.1,
    amplitude: 0.001,
    tessellation: Int32(maxTessellation)
  )

  override init() {
    device = Renderer.makeDevice()
    view = Renderer.makeView(device: device)
    let library = device.makeDefaultLibrary()!
    tessellationPipelineState = Renderer.makeComputePipelineState(device: device, library: library)
    renderPipelineState = Renderer.makeRenderPipelineState(device: device, library: library, metalView: view)
    depthStencilState = Renderer.makeDepthStencilState(device: device)!
    controlPointsBuffer = Renderer.makeControlPointsBuffer(patches: patches, terrain: Renderer.terrain, device: device)
    commandQueue = device.makeCommandQueue()!
    heightMap = Renderer.makeTexture(imageName: "mountain", device: device)
    noiseMap = Renderer.makeTexture(imageName: "noise", device: device)
    rockTexture = Renderer.makeTexture(imageName: "scratched", device: device)
    super.init()
    view.delegate = self
  }
  
  private static func makeDevice() -> MTLDevice {
    MTLCreateSystemDefaultDevice()!
  }
  
  private static func makeView(device: MTLDevice) -> MTKView {
    let metalView = MTKView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
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

  private func makeViewMatrix(eye: SIMD3<Float>) -> float4x4 {
    let at = SIMD3<Float>(0.0, 0.0, 0.0)
    let up = SIMD3<Float>(0.0, 1.0, 0.0)
    return look(at: at, eye: eye, up: up)
  }
  
  private func makeModelMatrix() -> float4x4 {
    let angle: Float = 0//Float(frameCounter) / Float(view.preferredFramesPerSecond) / 5
    let spin = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.0), by: -angle)
    return spin
  }
  
  private func makeProjectionMatrix() -> float4x4 {
    let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
    return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.001, farZ: 1000.0)
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

    let surface: Float = 0.001//Renderer.terrain.height * 1.02
    surfaceDistance *= 0.995
    let distance: Float = surface + surfaceDistance
    let eye = SIMD3<Float>(1, 0.8, distance)
    let modelMatrix = makeModelMatrix()
    let viewMatrix = makeViewMatrix(eye: eye)
    let projectionMatrix = makeProjectionMatrix()
    
    var uniforms = Uniforms(
      cameraPosition: eye,
      modelMatrix: modelMatrix,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      mvpMatrix: projectionMatrix * viewMatrix * modelMatrix
    )
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    
    // Tessellation pass.
    
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    computeEncoder.setComputePipelineState(tessellationPipelineState)
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
    
    renderEncoder.setFragmentTexture(rockTexture, index: 0)

    
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
    commandBuffer.commit()
  }
}
