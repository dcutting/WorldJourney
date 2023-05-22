import MetalKit

class Renderer: NSObject, MTKViewDelegate {
  private let fillMode: MTLTriangleFillMode = .fill
  private let patches = 64
  private let radius: Int32 = 8_388_608
  private lazy var fRadius = Float(radius)
  private lazy var dRadius = Double(radius)
  private var dTime: Double = 0
  private var dLod: Double = 1
  private let dLodFactor: Double = 100
  private lazy var fov: Float = calculateFieldOfView(degrees: 48)
  private let farZ: Float = 1000
  
  private let view: MTKView
  private let device = MTLCreateSystemDefaultDevice()!
  private lazy var commandQueue = device.makeCommandQueue()!
  private var pipelineState: MTLRenderPipelineState!
  private var depthStencilState: MTLDepthStencilState!
  //  let terrainTessellator: Tessellator
  private var topVertices = [simd_float2]()
  private var frontVertices = [simd_float2]()
  private var leftVertices = [simd_float2]()
  private var bottomVertices = [simd_float2]()
  private var backVertices = [simd_float2]()
  private var rightVertices = [simd_float2]()
  private let topBuffer: MTLBuffer
  private let frontBuffer: MTLBuffer
  private let leftBuffer: MTLBuffer
  private let bottomBuffer: MTLBuffer
  private let backBuffer: MTLBuffer
  private let rightBuffer: MTLBuffer
  
  enum Side: Int {
    case top, front, left, bottom, back, right
  }
  
  init?(metalKitView: MTKView) {
    self.view = metalKitView
    metalKitView.depthStencilPixelFormat = .depth32Float
    let library = device.makeDefaultLibrary()!
    pipelineState = Self.makePipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)
    
    (topVertices, topBuffer) = Self.makeGrid(patches: patches, device: device)
    (frontVertices, frontBuffer) = Self.makeGrid(patches: patches, device: device)
    (leftVertices, leftBuffer) = Self.makeGrid(patches: patches, device: device)
    (bottomVertices, bottomBuffer) = Self.makeGrid(patches: patches, device: device)
    (backVertices, backBuffer) = Self.makeGrid(patches: patches, device: device)
    (rightVertices, rightBuffer) = Self.makeGrid(patches: patches, device: device)
    
    //    terrainTessellator = Tessellator(device: device, library: library, patchesPerSide: Int(1))
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    
    dTime += 0.01
    
    //    let dEye: simd_double3 = simd_double3(dRadius*3*sin(dTime), dRadius/2, dRadius*3*cos(dTime))
    let dEye: simd_double3 = simd_double3(dRadius*2, dRadius*2, dRadius*2)
    updateLod(eye: dEye, lodFactor: dLodFactor)
    printAltitude(eye: dEye)
    
    let fEyeLod = simd_float3(dEye / dLod)
    let viewMatrix = look(at: .zero, eye: fEyeLod, up: simd_float3(0, 1, 0))
    let sunDistance = dRadius*10
    let dSun = simd_double3(sin(dTime)*sunDistance, 0, cos(dTime)*sunDistance)
    
    let fSunLod: simd_float3 = simd_float3(dSun / dLod)
    let fLod: Float = Float(dLod)
    let fRadiusLod: Float = Float(dRadius / dLod)
    
    let projectionMatrix = makeProjectionMatrix(w: view.bounds.width, h: view.bounds.height, fov: fov, farZ: farZ)
    
    var uniforms = Uniforms(
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      side: 0,
      lod: fLod,
      eyeLod: fEyeLod,
      radiusLod: fRadiusLod,
      sunLod: fSunLod,
      screenWidth: Int32(view.bounds.width),
      screenHeight: Int32(view.bounds.height)
    )
    
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.95, blue: 0.05, alpha: 1.0)
    
    //    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!//    terrainTessellator.doTessellationPass(computeEncoder: computeEncoder, uniforms: uniforms)
    //    computeEncoder.endEncoding()
    
    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    encoder.setTriangleFillMode(fillMode)
    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthStencilState)
    encoder.setCullMode(.back)
    
    //    let (factors, points, _, count) = terrainTessellator.getBuffers(uniforms: uniforms)
    //    encoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: 0)
    
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    
    //    encoder.drawPatches(numberOfPatchControlPoints: 4,
    //                              patchStart: 0,
    //                              patchCount: count,
    //                              patchIndexBuffer: nil,
    //                              patchIndexBufferOffset: 0,
    //                              instanceCount: 1,
    //                              baseInstance: 0)
    
    //    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertices.count)
    
    let drawTop =    true
    let drawFront =  true
    let drawLeft =   true
    let drawBottom = true
    let drawBack =   true
    let drawRight =  true
    
    // TOP
    if drawTop {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .top)
      encoder.setVertexBuffer(topBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 0
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.counterClockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: topVertices.count, instanceCount: count)
    }
    
    // FRONT
    if drawFront {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .front)
      encoder.setVertexBuffer(frontBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 1
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.clockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: frontVertices.count, instanceCount: count)
    }
    
    // LEFT
    if drawLeft {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .left)
      encoder.setVertexBuffer(leftBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 2
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.clockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: leftVertices.count, instanceCount: count)
    }
    
    // BOTTOM
    if drawBottom {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .bottom)
      encoder.setVertexBuffer(bottomBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 3
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.clockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bottomVertices.count, instanceCount: count)
    }
    
    // BACK
    if drawBack {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .back)
      encoder.setVertexBuffer(backBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 4
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.counterClockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: backVertices.count, instanceCount: count)
    }
    
    // RIGHT
    if drawRight {
      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .right)
      encoder.setVertexBuffer(rightBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
      uniforms.side = 5
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.counterClockwise)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rightVertices.count, instanceCount: count)
    }
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  func makeQuadUniformsBuffer(dEye: simd_double3, side: Side) -> (MTLBuffer, Int) {
    var array = makeQuadUniforms(dEye: dEye, side: side)
    let buffer = device.makeBuffer(length: MemoryLayout<QuadUniforms>.stride * array.count)!
    let bufferPtr = buffer.contents().bindMemory(to: QuadUniforms.self, capacity: array.count)
    bufferPtr.assign(from: &array, count: array.count)
    return (buffer, array.count)
  }
  
  func printAltitude(eye: SIMD3<Double>) {
    let altitudeM = length(eye) - dRadius
    let altitudeString = altitudeM < 1000 ? String(format: "%.1fm", altitudeM) : String(format: "%.2fkm", altitudeM / 1000)
    print("LOD: ", dLod, ", MSL altitude:", altitudeString)
  }
  
  func updateLod(eye: SIMD3<Double>, lodFactor: Double) {
    let dist = length(eye)
    dLod = floor(dist/lodFactor)
  }
  
  func makeQuadUniforms(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    return makeAdaptiveLod(dEye: dEye, side: side)
  }
  
  func makeStaticGrid(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
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
        case .bottom:
          origin = SIMD3<Double>(Double(si), Double(-radius), Double(sj))
        case .back:
          origin = SIMD3<Double>(Double(-radius), Double(si), Double(sj))
        case .right:
          origin = SIMD3<Double>(Double(si), Double(sj), Double(-radius))
        }
        let quadUniforms = makeQuad(origin: origin, quadScale: quadScale)
        quadUniformsArray.append(quadUniforms)
      }
    }
    
    return quadUniformsArray
  }
  
  func makeAdaptiveLod(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    let size: Int32 = radius*2
    var origin: SIMD3<Double>
    switch side {
    case .top:
      origin = SIMD3<Double>(Double(-radius), Double(radius), Double(-radius))
    case .front:
      origin = SIMD3<Double>(Double(radius), Double(-radius), Double(-radius))
    case .left:
      origin = SIMD3<Double>(Double(-radius), Double(-radius), Double(radius))
    case .bottom:
      origin = SIMD3<Double>(Double(-radius), Double(-radius), Double(-radius))
    case .back:
      origin = SIMD3<Double>(Double(-radius), Double(-radius), Double(-radius))
    case .right:
      origin = SIMD3<Double>(Double(-radius), Double(-radius), Double(-radius))
    }
    return makeAdaptiveLod(eye: dEye, corner: origin, size: size, side: side)
  }
  
  func makeAdaptiveLod(eye: SIMD3<Double>, corner: SIMD3<Double>, size: Int32, side: Side) -> [QuadUniforms] {
    let threshold: Double = Double(size*4)
    let half = size / 2
    let dHalf = Double(half)
    let center = corner + dHalf
    let surfaceCenter = normalize(center) * Double(radius)
    let d = distance(eye, surfaceCenter)
    if size == 1 || d > threshold {
      return [makeQuad(origin: corner, quadScale: size)]
    }
    let q1d: simd_double3
    let q2d: simd_double3
    let q3d: simd_double3
    switch side {
    case .top, .bottom:
      q1d = simd_double3(dHalf, 0, 0)
      q2d = simd_double3(0, 0, dHalf)
      q3d = simd_double3(dHalf, 0, dHalf)
    case .front, .back:
      q1d = simd_double3(0, dHalf, 0)
      q2d = simd_double3(0, 0, dHalf)
      q3d = simd_double3(0, dHalf, dHalf)
    case .left, .right:
      q1d = simd_double3(dHalf, 0, 0)
      q2d = simd_double3(0, dHalf, 0)
      q3d = simd_double3(dHalf, dHalf, 0)
    }
    let q0 = makeAdaptiveLod(eye: eye, corner: corner, size: half, side: side)
    let q1 = makeAdaptiveLod(eye: eye, corner: corner + q1d, size: half, side: side)
    let q2 = makeAdaptiveLod(eye: eye, corner: corner + q2d, size: half, side: side)
    let q3 = makeAdaptiveLod(eye: eye, corner: corner + q3d, size: half, side: side)
    return q0 + q1 + q2 + q3
  }
  
  func makeQuad(origin: SIMD3<Double>, quadScale: Int32) -> QuadUniforms {
    let translation = SIMD3<Float>(origin / dLod)
    let scale: Float = Float(Double(quadScale) / dLod)
    let quadMatrix = float4x4(translationBy: translation) * float4x4(scaleBy: scale)
    let cube: vector_int3 = SIMD3<Int32>(Int32(floor(origin.x)), Int32(floor(origin.y)), Int32(floor(origin.z)))
    let quadUniforms = QuadUniforms(modelMatrix: quadMatrix, cubeOrigin: cube, cubeSize: quadScale)
    return quadUniforms
  }
}

extension Renderer {
  private static func makeGrid(patches: Int, device: MTLDevice) -> ([simd_float2], MTLBuffer) {
    let vertices = Self.createVertexPoints(patches: patches, size: 1)
    return (
      vertices,
      Self.makeGridBuffer(vertices: vertices, device: device)
    )
  }
  
  private static func makeGridBuffer(vertices: [simd_float2], device: MTLDevice) -> MTLBuffer {
    device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<simd_float2>.stride, options: [])!
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
    return points
  }
}

extension Renderer {
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
