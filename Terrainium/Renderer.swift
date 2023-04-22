import MetalKit

let fillMode: MTLTriangleFillMode = .lines

class Renderer: NSObject, MTKViewDelegate {
  private let view: MTKView
  private let device = MTLCreateSystemDefaultDevice()!
  private lazy var commandQueue = device.makeCommandQueue()!
  private var pipelineState: MTLRenderPipelineState!
  private var depthStencilState: MTLDepthStencilState!
  private let fov: Float
  private var gridTopVertices = [simd_float2]()
  private var gridFrontVertices = [simd_float2]()
  private var gridLeftVertices = [simd_float2]()
  private var levelVertices = [simd_float2]()
  private let gridTopBuffer: MTLBuffer
  private let gridFrontBuffer: MTLBuffer
  private let gridLeftBuffer: MTLBuffer
  private let levelBuffer: MTLBuffer
  private var time: Double = 0
//  let terrainTessellator: Tessellator
  private let radius: Int32 = 6371000
  private let patches = 64
  private var lod: Double = 1

  init?(metalKitView: MTKView) {
    self.view = metalKitView
    metalKitView.depthStencilPixelFormat = .depth32Float
    fov = calculateFieldOfView(degrees: 48)
    let library = device.makeDefaultLibrary()!
    pipelineState = Self.makePipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)
    gridTopVertices = Self.createVertexPoints(patches: patches, size: 1)
    gridFrontVertices = Self.createVertexPoints(patches: patches, size: 1)
    gridLeftVertices = Self.createVertexPoints(patches: patches, size: 1)
    levelVertices = Self.createVertexPoints(patches: 1, size: 1)
    gridTopBuffer = device.makeBuffer(bytes: gridTopVertices, length: gridTopVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    gridFrontBuffer = device.makeBuffer(bytes: gridFrontVertices, length: gridFrontVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    gridLeftBuffer = device.makeBuffer(bytes: gridLeftVertices, length: gridLeftVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    levelBuffer = device.makeBuffer(bytes: levelVertices, length: levelVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
//    terrainTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(1))
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
                                                farZ: 1000.0)
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
    time += 0.01
    let distance: Double = 700
    let height: Double = (1 + sin(-time*0.6))/2.0 * 1000 + 0.5//sin(time*0)*2+6
    let rot: Double = time * 0
    // Note: eye needs to be a double
//    let eye = simd_float3(distance, 200, distance)
//    let eye = simd_double3(cos(time*0.1) * distance, height, sin(time*0.15) * distance)
    let eye = simd_double3(cos(time*0.1)*Double(radius), sin(time*0.1)*Double(radius), sin(time*300000) + Double(radius))
//    let eye = simd_float3(sin(time)*3, 16, cos(time)*3)
//    let eye = simd_float3(cos(time)*distance, 0, -sin(time)*distance)
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time*3)*0.3, sin(time)*1+2.5, 2.5), up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(time*3-3, 0.7, 4), up: simd_float3(0, 1, 0))
    let eyeFloat = simd_float3(eye / lod)
    print("eyeDbl", eye)
    print("eyeFlt", eyeFloat)
    let viewMatrix = look(at: .zero, eye: eyeFloat, up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time*2)/2, 0.7, 1), up: simd_float3(0, 1, 0))
//    let eye = simd_float3(0, 0.5, 1);
//    let viewMatrix = matrix_float4x4(translationBy: -eye)
    let modelMatrix = matrix_float4x4(diagonal: simd_float4(repeating: 1))
    
    var uniforms = Uniforms(modelMatrix: modelMatrix,
                            viewMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            eye: eyeFloat,
                            ambientColour: simd_float3(0.2, 0.2, 0.2),
                            drawLevel: 0,
                            level: 0.0,
                            time: Float(time),
                            screenWidth: Int32(view.bounds.width),
                            screenHeight: Int32(view.bounds.height),
                            side: 0,
                            radius: Float(radius),
                            lod: Float(lod),
                            radiusLod: Float(Double(radius)/lod)
    )

    
//    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//    terrainTessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: uniforms)
//    computeEncoder.endEncoding()

    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    encoder.setTriangleFillMode(fillMode)
    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthStencilState)
//    encoder.setCullMode(.none)

//    let (factors, points, _, count) = terrainTessellator.getBuffers(uniforms: uniforms)
//    encoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: 0)

    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

    var topQuadUniformsArray = makeQuadUniforms(eye: eye, side: .top)
    let topQuadUniformsBuffer = device.makeBuffer(length: MemoryLayout<QuadUniforms>.stride * topQuadUniformsArray.count)!
    let topQuadUniformsBufferPtr = topQuadUniformsBuffer.contents().bindMemory(to: QuadUniforms.self,
                                                                         capacity: topQuadUniformsArray.count)
    topQuadUniformsBufferPtr.assign(from: &topQuadUniformsArray, count: topQuadUniformsArray.count)
    encoder.setVertexBuffer(gridTopBuffer, offset: 0, index: 0)
    encoder.setVertexBuffer(topQuadUniformsBuffer, offset: 0, index: 2)
    uniforms.side = 0
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

//    encoder.drawPatches(numberOfPatchControlPoints: 4,
//                              patchStart: 0,
//                              patchCount: count,
//                              patchIndexBuffer: nil,
//                              patchIndexBufferOffset: 0,
//                              instanceCount: 1,
//                              baseInstance: 0)
    
//    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertices.count)
    
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridTopVertices.count, instanceCount: topQuadUniformsArray.count)

    var frontQuadUniformsArray = makeQuadUniforms(eye: eye, side: .front)
    let frontQuadUniformsBuffer = device.makeBuffer(length: MemoryLayout<QuadUniforms>.stride * frontQuadUniformsArray.count)!
    let frontQuadUniformsBufferPtr = frontQuadUniformsBuffer.contents().bindMemory(to: QuadUniforms.self,
                                                                         capacity: frontQuadUniformsArray.count)
    frontQuadUniformsBufferPtr.assign(from: &frontQuadUniformsArray, count: frontQuadUniformsArray.count)
    encoder.setVertexBuffer(gridFrontBuffer, offset: 0, index: 0)
    encoder.setVertexBuffer(frontQuadUniformsBuffer, offset: 0, index: 2)
    uniforms.side = 1
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridFrontVertices.count, instanceCount: frontQuadUniformsArray.count)

    var leftQuadUniformsArray = makeQuadUniforms(eye: eye, side: .left)
    let leftQuadUniformsBuffer = device.makeBuffer(length: MemoryLayout<QuadUniforms>.stride * leftQuadUniformsArray.count)!
    let leftQuadUniformsBufferPtr = leftQuadUniformsBuffer.contents().bindMemory(to: QuadUniforms.self,
                                                                         capacity: leftQuadUniformsArray.count)
    leftQuadUniformsBufferPtr.assign(from: &leftQuadUniformsArray, count: leftQuadUniformsArray.count)
    encoder.setVertexBuffer(gridLeftBuffer, offset: 0, index: 0)
    encoder.setVertexBuffer(leftQuadUniformsBuffer, offset: 0, index: 2)
    uniforms.side = 2
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridLeftVertices.count, instanceCount: leftQuadUniformsArray.count)

//    let drawLevels = true
//    if drawLevels {
//      encoder.setVertexBuffer(levelBuffer, offset: 0, index: 0)
//      encoder.setTriangleFillMode(fillMode)
//      var uniforms2 = Uniforms(modelMatrix: modelMatrix,
//                               viewMatrix: viewMatrix,
//                               projectionMatrix: projectionMatrix,
//                               eye: eye,
//                               ambientColour: simd_float3(0, 0, 1),
//                               drawLevel: 10,
//                               level: 0.0,
//                               time: time,
//                               screenWidth: Int32(view.bounds.width),
//                               screenHeight: Int32(view.bounds.height))
//      encoder.setVertexBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFragmentBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 0)
//
//      encoder.drawPatches(numberOfPatchControlPoints: 4,
//                                patchStart: 0,
//                                patchCount: count,
//                                patchIndexBuffer: nil,
//                                patchIndexBufferOffset: 0,
//                                instanceCount: 1,
//                                baseInstance: 0)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
//      var uniforms3 = Uniforms(modelMatrix: modelMatrix,
//                               viewMatrix: viewMatrix,
//                               projectionMatrix: projectionMatrix,
//                               eye: eye,
//                               ambientColour: simd_float3(0, 0, 1),
//                               drawLevel: 1,
//                               level: 0.0,
//                               time: time,
//                               screenWidth: Int32(view.bounds.width),
//                               screenHeight: Int32(view.bounds.height))
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
//                               time: time,
//                               screenWidth: Int32(view.bounds.width),
//                               screenHeight: Int32(view.bounds.height))
//     encoder.setVertexBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFragmentBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 0)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
//    }
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  enum Side: Int {
    case top, front, left//, bottom, back, right
  }
  
  func makeQuadUniforms(eye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    let dist = length(eye)// - Double(radius)
//    lod = floor(log2(dist))
    lod = floor(dist/100.0)
    print(dist, lod)
    return makeUniformGrid(eye: eye, side: side)
  }
  
  func makeUniformGrid(eye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    var quadUniformsArray = [QuadUniforms]()
    
    let quadCount: Int32 = 1
    let quadScale: Int32 = radius/quadCount  // powers of 2 from 32 on make the noise completely flat!
        
    for j in -quadCount..<quadCount {
      for i in -quadCount..<quadCount {
        let si = quadScale * Int32(i)
        let sj = quadScale * Int32(j)
        let origin: SIMD3<Double>
        switch side {
        case .top:
          origin = SIMD3<Double>(Double(si), Double(radius), Double(sj))
        case .front:
          origin = SIMD3<Double>(Double(radius), Double(si), Double(sj))
        case .left:
          origin = SIMD3<Double>(Double(si), Double(sj), Double(radius))
//        case .bottom:
//          origin = SIMD3<Float>(Float32(si), Float32(radius), Float32(sj))
//        case .back:
//          origin = SIMD3<Float>(Float32(si), Float32(radius), Float32(sj))
//        case .right:
//          origin = SIMD3<Float>(Float32(si), Float32(radius), Float32(sj))
        }
        let quadUniforms = makeQuad(origin: origin, quadScale: quadScale)
        quadUniformsArray.append(quadUniforms)
      }
    }
    
    return quadUniformsArray
  }

//  func makeHardcodedLod(eye: SIMD3<Double>) -> [QuadUniforms] {
//    // 3 big squares
//    let c00 = makeQuad(origin: SIMD3<Float>(-64, 0, -64), quadScale: 64)
//    let c01 = makeQuad(origin: SIMD3<Float>(0, 0, -64), quadScale: 64)
//    let c10 = makeQuad(origin: SIMD3<Float>(-64, 0, 0), quadScale: 64)
////    let c11 = makeQuad(origin: SIMD3<Float>(0, 0, 0), quadScale: 64)
////    let c1100 = makeQuad(origin: SIMD3<Float>(0, 0, 0), quadScale: 32)
////    let c110000 = makeQuad(origin: SIMD3<Float>(0, 0, 0), quadScale: 16)
//    let c11000000 = makeQuad(origin: SIMD3<Float>(0, 0, 0), quadScale: 8)
//    let c11000001 = makeQuad(origin: SIMD3<Float>(8, 0, 0), quadScale: 8)
//    let c11000010 = makeQuad(origin: SIMD3<Float>(0, 0, 8), quadScale: 8)
//    let c11000011 = makeQuad(origin: SIMD3<Float>(8, 0, 8), quadScale: 8)
//    let c110001 = makeQuad(origin: SIMD3<Float>(16, 0, 0), quadScale: 16)
//    let c110010 = makeQuad(origin: SIMD3<Float>(0, 0, 16), quadScale: 16)
//    let c110011 = makeQuad(origin: SIMD3<Float>(16, 0, 16), quadScale: 16)
//    let c1101 = makeQuad(origin: SIMD3<Float>(32, 0, 0), quadScale: 32)
//    let c1110 = makeQuad(origin: SIMD3<Float>(0, 0, 32), quadScale: 32)
//    let c1111 = makeQuad(origin: SIMD3<Float>(32, 0, 32), quadScale: 32)
//    return [c00, c01, c10, c11000000, c11000001, c11000010, c11000011, c110001, c110010, c110011, c1101, c1110, c1111]
//  }
//
//  func makeAdaptiveLod(eye: SIMD3<Double>) -> [QuadUniforms] {
//    let size: Int32 = 1024
//    let corner = SIMD3<Double>(repeating: -Double(size)/2.0)
//    return makeAdaptiveLod(eye: eye, corner: corner, size: size)
//  }
//
//  func makeAdaptiveLod(eye: SIMD3<Double>, corner: SIMD3<Double>, size: Int32) -> [QuadUniforms] {
//    let threshold: Double = Double(size)
//    let half = size / 2
//    let dHalf = Double(half)
//    let center = corner + dHalf
//    let d = distance(eye, center)
//    if size == 1 || d > threshold {
//      return [makeQuad(origin: corner, quadScale: size)]
//    }
//    let q0 = makeAdaptiveLod(eye: eye, corner: corner, size: half)
//    let q1 = makeAdaptiveLod(eye: eye, corner: corner + simd_double3(dHalf, 0, 0), size: half)
//    let q2 = makeAdaptiveLod(eye: eye, corner: corner + simd_double3(0, 0, dHalf), size: half)
//    let q3 = makeAdaptiveLod(eye: eye, corner: corner + simd_double3(dHalf, 0, dHalf), size: half)
//    return q0 + q1 + q2 + q3
//  }
  
  func makeQuad(origin: SIMD3<Double>, quadScale: Int32) -> QuadUniforms {
    let translation = SIMD3<Float>(origin / lod)
    let scale: Float = Float(Double(quadScale) / lod)
    print("origin, quadScale", origin, quadScale)
    print("translation, scale", translation, scale)
    let quadMatrix = float4x4(translationBy: translation) * float4x4(scaleBy: scale)
    let cube: vector_int3 = SIMD3<Int32>(Int32(floor(origin.x)), Int32(floor(origin.y)), Int32(floor(origin.z)))
    let quadUniforms = QuadUniforms(modelMatrix: quadMatrix, cubeOrigin: cube, cubeSize: quadScale)
    return quadUniforms
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
//    let hSize: Float = size / 2.0
//    points = points.map {
//      [$0.x - hSize,
//       ($0.y - hSize)]
//    }
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
//    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    descriptor.vertexDescriptor = vertexDescriptor
    
//    descriptor.tessellationFactorStepFunction = .perPatch
//    descriptor.maxTessellationFactor = 64
//    descriptor.tessellationPartitionMode = .fractionalEven
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
    let controlPoints = createControlPoints(patches: patches, size: 4)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!,
            controlPoints.count / 4)
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
