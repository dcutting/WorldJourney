import MetalKit

let fillMode: MTLTriangleFillMode = .fill

class Renderer: NSObject, MTKViewDelegate {
  private let view: MTKView
  private let device = MTLCreateSystemDefaultDevice()!
  private lazy var commandQueue = device.makeCommandQueue()!
  private var pipelineState: MTLRenderPipelineState!
  private var depthStencilState: MTLDepthStencilState!
  private let fov: Float
  private var gridVertices = [simd_float2]()
  private var levelVertices = [simd_float2]()
  private let gridBuffer: MTLBuffer
  private let levelBuffer: MTLBuffer
  private var time: Float = 0
  let terrainTessellator: Tessellator

  init?(metalKitView: MTKView) {
    self.view = metalKitView
    metalKitView.depthStencilPixelFormat = .depth32Float
    fov = calculateFieldOfView(degrees: 48)
    let library = device.makeDefaultLibrary()!
    pipelineState = Self.makePipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)
    gridVertices = Self.createVertexPoints(patches: 1024, size: 48)
    levelVertices = Self.createVertexPoints(patches: 1, size: 60)
    gridBuffer = device.makeBuffer(bytes: gridVertices, length: gridVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    levelBuffer = device.makeBuffer(bytes: levelVertices, length: levelVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    terrainTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(32))
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
  }
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    let projectionMatrix = makeProjectionMatrix(w: view.bounds.width,
                                                h: view.bounds.height,
                                                fov: fov,
                                                farZ: 700.0)
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
    time += 0.001
    let distance: Float = 100//sin(time*0)*2+6
    let rot: Float = time * 0
//    let eye = simd_float3(distance, 16, distance)
//    let eye = simd_float3(cos(time) * distance, 8, sin(time) * distance)
//    let eye = simd_float3(sin(time)*3, 16, cos(time)*3)
    let eye = simd_float3(cos(time*1.3)*distance, sin(time*5.9)*2+3, -sin(time*1.6)*52)
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time*3)*0.3, sin(time)*1+2.5, 2.5), up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(time*3-3, 0.7, 4), up: simd_float3(0, 1, 0))
    let viewMatrix = look(at: .zero, eye: eye, up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time*2)/2, 0.7, 1), up: simd_float3(0, 1, 0))
//    let eye = simd_float3(0, 0.5, 1);
//    let viewMatrix = matrix_float4x4(translationBy: -eye)
    let modelMatrix = matrix_float4x4(diagonal: simd_float4(repeating: 1))
    
    var uniforms = Uniforms(modelMatrix: modelMatrix,
                            viewMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            eye: eye,
                            ambientColour: simd_float3(0.2, 0.2, 0.2),
                            drawLevel: 0,
                            level: 0.0,
                            time: time,
                            screenWidth: Int32(view.bounds.width),
                            screenHeight: Int32(view.bounds.height))

    
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    terrainTessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: uniforms)
    computeEncoder.endEncoding()

    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    encoder.setTriangleFillMode(fillMode)
    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthStencilState)
//    encoder.setCullMode(.none)

    let (factors, points, _, count) = terrainTessellator.getBuffers(uniforms: uniforms)
    encoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: 0)

    encoder.setVertexBuffer(points, offset: 0, index: 0)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

    encoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0,
                              patchCount: count,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1,
                              baseInstance: 0)
//    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertices.count)
    
//    let drawLevels = false
//    if drawLevels {
//      encoder.setVertexBuffer(levelBuffer, offset: 0, index: 0)
//      encoder.setTriangleFillMode(fillMode)
//      var uniforms2 = Uniforms(modelMatrix: modelMatrix,
//                               viewMatrix: viewMatrix,
//                               projectionMatrix: projectionMatrix,
//                               eye: eye,
//                               ambientColour: simd_float3(0, 0, 1),
//                               drawLevel: 1,
//                               level: -1.0,
//                               time: time)
//      encoder.setVertexBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFragmentBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 0)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
//      var uniforms3 = Uniforms(modelMatrix: modelMatrix,
//                               viewMatrix: viewMatrix,
//                               projectionMatrix: projectionMatrix,
//                               eye: eye,
//                               ambientColour: simd_float3(0, 0, 1),
//                               drawLevel: 1,
//                               level: 0.0,
//                               time: time)
//      encoder.setVertexBytes(&uniforms3, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFragmentBytes(&uniforms3, length: MemoryLayout<Uniforms>.stride, index: 0)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
//      var uniforms4 = Uniforms(modelMatrix: modelMatrix,
//                               viewMatrix: viewMatrix,
//                               projectionMatrix: projectionMatrix,
//                               eye: eye,
//                               ambientColour: simd_float3(0, 0, 1),
//                               drawLevel: 1,
//                               level: 1.0,
//                               time: time)
//      encoder.setVertexBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFragmentBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 0)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
//    }
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  private static func createVertexPoints(patches: Int, size: Float) -> [simd_float2] {
    var points: [simd_float2] = []
    let width: Float = size / Float(patches)

    for j in 0..<patches {
      let row: Float = Float(j)
      for i in 0..<patches {
        let column: Float = Float(i)
        let left: Float = width * column
        let bottom: Float = width * row
        let right: Float = width * column + width
        let top: Float = width * row + width
        points.append([left, top])
        points.append([right, top])
        points.append([left, bottom])
        points.append([right, top])
        points.append([right, bottom])
        points.append([left, bottom])
      }
    }
    // size and convert to Metal coordinates
    // eg. 6 across would be -3 to + 3
    let hSize: Float = size / 2.0
    points = points.map {
      [$0.x - hSize,
       ($0.y - hSize)]
    }
    return points
  }

  
  private static func makePipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.vertexFunction = library.makeFunction(name: "terrainium_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "terrainium_fragment")
    
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    descriptor.vertexDescriptor = vertexDescriptor
    
    descriptor.tessellationFactorStepFunction = .perPatch
    descriptor.maxTessellationFactor = 64
    descriptor.tessellationPartitionMode = .fractionalEven
    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: descriptor)!
  }
}

class Tessellator {
  let tessellationPipelineState: MTLComputePipelineState
  let controlPointsBuffer: MTLBuffer
  let tessellationFactorsBuffer: MTLBuffer
  let patchCount: Int
  let patchesPerSide: Int

  init(device: MTLDevice, library: MTLLibrary, patchesPerSide: Int) {
    self.patchesPerSide = patchesPerSide
    self.tessellationPipelineState = Self.makeTessellationPipelineState(device: device, library: library)
    (self.controlPointsBuffer, self.patchCount) = Self.makeControlPointsBuffer(patches: patchesPerSide, device: device)
    self.tessellationFactorsBuffer = Self.makeFactorsBuffer(device: device, patchCount: patchCount)
  }
  
  private static func makeTessellationPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "tessellation_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Tessellation kernel function not found.") }
    return state
  }
  
  private static func makeControlPointsBuffer(patches: Int, device: MTLDevice) -> (MTLBuffer, Int) {
    let controlPoints = createControlPoints(patches: patches, size: 200)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!, controlPoints.count / 4)
  }
  
  private static func makeFactorsBuffer(device: MTLDevice, patchCount: Int) -> MTLBuffer {
    let count = patchCount * (4 + 2)  // 4 edges + 2 insides
    let size = count * MemoryLayout<Float>.size / 2 // "half floats"
    return device.makeBuffer(length: size, options: .storageModePrivate)!
  }
  
  func getBuffers(uniforms: Uniforms) -> (MTLBuffer, MTLBuffer, Int, Int) {
    (tessellationFactorsBuffer, controlPointsBuffer, patchesPerSide, patchCount)
  }

  func doTessellationPass(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms) {
    let (factors, points, _, count) = getBuffers(uniforms: uniforms)
    var uniforms = uniforms
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setBuffer(factors, offset: 0, index: 2)
    computeEncoder.setBuffer(points, offset: 0, index: 3)
    computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
    // TODO: don't want to use terrain for ocean tessellation
//    computeEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 5)
    let width = min(count, tessellationPipelineState.threadExecutionWidth)
    computeEncoder.dispatchThreads(
      MTLSizeMake(count, 1, 1),
      threadsPerThreadgroup: MTLSizeMake(width, 1, 1)
    )
  }
}

func createControlPoints(patches: Int, size: Float) -> [SIMD3<Float>] {
  var points: [SIMD3<Float>] = []
  let patchWidth = 1 / Float(patches)
  let start = 0
  let end = patches
  for j in start..<end {
    let row = Float(j)
    for i in start..<end {
      let column = Float(i)
      let left = patchWidth * column
      let bottom = patchWidth * row
      let right = patchWidth * column + patchWidth
      let top = patchWidth * row + patchWidth
      points.append([left, top, 0])
      points.append([right, top, 0])
      points.append([right, bottom, 0])
      points.append([left, bottom, 0])
    }
  }
  // Size and convert to Metal coordinates. E.g., 6 across would be -3 to + 3.
  points = points.map {[
    $0.x * size - size / 2,
    $0.y * size - size / 2,
    0
  ]}
  return points
}
