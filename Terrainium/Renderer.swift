import MetalKit

class Renderer: NSObject, MTKViewDelegate {
  private let fillMode: MTLTriangleFillMode = .fill
  private let patches = 1
  private let thresholdFactor = 1.6
  private let iRadius: Int32 = 6_371_000
  private lazy var fRadius = Float(iRadius)
  private lazy var dRadius = Double(iRadius)
  private var dTime: Double = 0// 9.3
  private var dLod: Double = 1
  private var fLod: Float = 1
  private let dLodFactor: Double = 1000
  private var dEye: simd_double3 = .zero
  private var dEyeLod: simd_double3 = .zero
  private var fEye: simd_float3 = .zero
  private var fEyeLod: simd_float3 = .zero
  private lazy var fov: Double = calculateFieldOfView(degrees: 48)
  private let farZ: Double = 3000
  private let drawTop =    true
//  private let drawFront =  false
//  private let drawLeft =   false
//  private let drawBottom = false
//  private let drawBack =   false
//  private let drawRight =  false

  private var viewMatrix: double4x4!
  private var vp: double4x4!
  private let view: MTKView
  private let device = MTLCreateSystemDefaultDevice()!
  private lazy var commandQueue = device.makeCommandQueue()!
  private var pipelineState: MTLRenderPipelineState!
  private var depthStencilState: MTLDepthStencilState!
    let terrainTessellator: Tessellator
  private var topVertices = [simd_float2]()
//  private var frontVertices = [simd_float2]()
//  private var leftVertices = [simd_float2]()
//  private var bottomVertices = [simd_float2]()
//  private var backVertices = [simd_float2]()
//  private var rightVertices = [simd_float2]()
  private let topBuffer: MTLBuffer
//  private let frontBuffer: MTLBuffer
//  private let leftBuffer: MTLBuffer
//  private let bottomBuffer: MTLBuffer
//  private let backBuffer: MTLBuffer
//  private let rightBuffer: MTLBuffer
  
  enum Side: Int {
    case top    = 0
//    case front  = 1
//    case left   = 2
//    case bottom = 3
//    case back   = 4
//    case right  = 5
  }
  
  init?(metalKitView: MTKView) {
    self.view = metalKitView
    metalKitView.depthStencilPixelFormat = .depth32Float
    let library = device.makeDefaultLibrary()!
    pipelineState = Self.makePipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)
    
    (topVertices, topBuffer) = Self.makeGrid(patches: patches, device: device)
//    (frontVertices, frontBuffer) = Self.makeGrid(patches: patches, device: device)
//    (leftVertices, leftBuffer) = Self.makeGrid(patches: patches, device: device)
//    (bottomVertices, bottomBuffer) = Self.makeGrid(patches: patches, device: device)
//    (backVertices, backBuffer) = Self.makeGrid(patches: patches, device: device)
//    (rightVertices, rightBuffer) = Self.makeGrid(patches: patches, device: device)
    
    terrainTessellator = Tessellator(device: device, library: library)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    
    dTime += 0.01
//    let fTime = Float(dTime)
    let dAmplitude: Double = 8848
    
    let y = dRadius + dAmplitude*1.905// + (dRadius*0.1) / (dTime*100.0)
//    let y = dRadius + (dAmplitude * 3 / dTime*10.0)// + (dRadius*0.1) / (dTime*100.0)
    dEye = simd_double3(sin(dTime/2)*1000, y+sin(dTime/3.15)*1000, dTime*1500 - 5000500)
//    dEye = simd_double3(dRadius / 2, y, dRadius - dTime * 100000)
//    let y = dRadius + (dRadius*0.1) / (dTime*100.0)
//    let dEye: simd_double3 = simd_double3(sin(dTime/2)*1000, y, dTime*1500 - 5000500)
    updateLod(eye: dEye, lodFactor: dLodFactor)
    dEyeLod = dEye / dLod
    fEyeLod = simd_float3(dEyeLod)
    printAltitude(eye: dEye)

    let fRadiusLod: Float = Float(dRadius / dLod)
    let fAmplitudeLod: Float = Float(dAmplitude / dLod)
    
    let at = simd_double3(0, ((dRadius + dAmplitude*1.7)/dLod), 0)
    let up = simd_double3((sin(dTime * 3.4) * 0.5 * cos(dTime*2.19213) * 0.2), 1, 0)
//    let up = simd_double3(0, 1, 0)
    viewMatrix = look(at: at, eye: dEyeLod, up: up)
    let dSun = simd_double3(10*dRadius, 4*dRadius, 1*dRadius)
    let fSunLod: simd_float3 = simd_float3(dSun / dLod)
    
    let projectionMatrix = makeProjectionMatrix(w: view.bounds.width, h: view.bounds.height, fov: fov, farZ: farZ)
    
    vp = projectionMatrix * viewMatrix;
    
    var uniforms = Uniforms(
//      viewMatrix: float4x4(viewMatrix),
//      projectionMatrix: float4x4(projectionMatrix),
//      side: 0,
      lod: fLod,
      eyeLod: fEyeLod,
      radiusLod: fRadiusLod,
      amplitudeLod: fAmplitudeLod,
      sunLod: fSunLod
//      screenWidth: Int32(view.bounds.width),
//      screenHeight: Int32(view.bounds.height),
//      time: fTime
    )
    
//    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1.0)
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)

    let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .top)
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    let factors = terrainTessellator.doTessellationPass(computeEncoder: computeEncoder,
                                                        uniforms: uniforms,
                                                        points: topBuffer,
                                                        quadUniforms: buffer,
                                                        patchCount: count)
    computeEncoder.endEncoding()

    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    encoder.setTriangleFillMode(fillMode)
    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthStencilState)
    encoder.setCullMode(.back)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

//    if drawTop {
      
      //    let (factors, points, _, count) = terrainTessellator.getBuffers(uniforms: uniforms)
//    let instanceStride: Int = Int((Double(MemoryLayout<SIMD2<Float>>.stride)/2.0) * (4+2))
    _ = (4 + 2)  // 4 edges + 2 insides
    let instanceStride = 0//floatCount * MemoryLayout<Float>.stride
    encoder.setTessellationFactorBuffer(factors, offset: 0, instanceStride: instanceStride)
      
      //      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertices.count)
//    }
    
    // TOP
//    if drawTop {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .top)
      encoder.setVertexBuffer(topBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 0
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFrontFacing(.counterClockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: topVertices.count, instanceCount: count)
      encoder.drawPatches(numberOfPatchControlPoints: 4,
                          patchStart: 0,
                          patchCount: 1,
                          patchIndexBuffer: nil,
                          patchIndexBufferOffset: 0,
                          instanceCount: count,
                          baseInstance: 0)
//    }
    
//    // FRONT
//    if drawFront {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .front)
//      encoder.setVertexBuffer(frontBuffer, offset: 0, index: 0)
//      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 1
//      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFrontFacing(.clockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: frontVertices.count, instanceCount: count)
//    }
//
//    // LEFT
//    if drawLeft {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .left)
//      encoder.setVertexBuffer(leftBuffer, offset: 0, index: 0)
//      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 2
//      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFrontFacing(.clockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: leftVertices.count, instanceCount: count)
//    }
//
//    // BOTTOM
//    if drawBottom {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .bottom)
//      encoder.setVertexBuffer(bottomBuffer, offset: 0, index: 0)
//      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 3
//      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFrontFacing(.clockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bottomVertices.count, instanceCount: count)
//    }
//
//    // BACK
//    if drawBack {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .back)
//      encoder.setVertexBuffer(backBuffer, offset: 0, index: 0)
//      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 4
//      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFrontFacing(.counterClockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: backVertices.count, instanceCount: count)
//    }
//
//    // RIGHT
//    if drawRight {
//      let (buffer, count) = makeQuadUniformsBuffer(dEye: dEye, side: .right)
//      encoder.setVertexBuffer(rightBuffer, offset: 0, index: 0)
//      encoder.setVertexBuffer(buffer, offset: 0, index: 2)
//      uniforms.side = 5
//      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
//      encoder.setFrontFacing(.counterClockwise)
//      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rightVertices.count, instanceCount: count)
//    }
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  func makeQuadUniformsBuffer(dEye: simd_double3, side: Side) -> (MTLBuffer, Int) {
    var array = makeGrid(dEye: dEye, side: side)
    let buffer = device.makeBuffer(length: MemoryLayout<QuadUniforms>.stride * array.count)!
    let bufferPtr = buffer.contents().bindMemory(to: QuadUniforms.self, capacity: array.count)
    bufferPtr.assign(from: &array, count: array.count)
    return (buffer, array.count)
  }
  
  func printAltitude(eye: SIMD3<Double>) {
//    let altitudeM = length(eye) - dRadius
    let altitudeM = eye.y - dRadius
    let altitudeString = altitudeM < 1000 ? String(format: "%.1fm", altitudeM) : String(format: "%.2fkm", altitudeM / 1000)
    let timeString = String(format: "%.4f", dTime)
    print("Time: ", timeString, ", LOD: ", dLod, ", FLOD: ", fLod, ", MSL altitude:", altitudeString)
  }
  
  func updateLod(eye: SIMD3<Double>, lodFactor: Double) {
    let dist = length(eye)
    dLod = floor(dist/lodFactor)
    fLod = Float(dLod)
  }
  
  func makeGrid(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    return makeAdaptiveGrid(dEye: dEye, side: side)
//    return makeStaticGrid(dEye: dEye, side: side)
  }
  
//  func makeStaticGrid(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
//    var quadUniformsArray = [QuadUniforms]()
//
//    for j in -1..<1 {
//      for i in -1..<1 {
//        let si = iRadius * Int32(i)
//        let sj = iRadius * Int32(j)
//        let origin: SIMD3<Double>
//        let cubeOrigin: SIMD3<Double>
//        switch side {
//        case .top:
//          origin = SIMD3<Double>(Double(i), Double(1), Double(j))
//          cubeOrigin = SIMD3<Double>(Double(si), Double(iRadius), Double(sj))
//        case .front:
//          origin = SIMD3<Double>(Double(1), Double(i), Double(j))
//          cubeOrigin = SIMD3<Double>(Double(iRadius), Double(si), Double(sj))
//        case .left:
//          origin = SIMD3<Double>(Double(i), Double(j), Double(1))
//          cubeOrigin = SIMD3<Double>(Double(si), Double(sj), Double(iRadius))
//        case .bottom:
//          origin = SIMD3<Double>(Double(i), Double(-1), Double(j))
//          cubeOrigin = SIMD3<Double>(Double(si), Double(-iRadius), Double(sj))
//        case .back:
//          origin = SIMD3<Double>(Double(-1), Double(i), Double(j))
//          cubeOrigin = SIMD3<Double>(Double(-iRadius), Double(si), Double(sj))
//        case .right:
//          origin = SIMD3<Double>(Double(i), Double(j), Double(-1))
//          cubeOrigin = SIMD3<Double>(Double(si), Double(sj), Double(-iRadius))
//        }
//        let quadUniforms = makeQuad(origin: origin, quadScale: 1, cubeOrigin: cubeOrigin, cubeSize: dRadius)
//        quadUniformsArray.append(quadUniforms)
//      }
//    }
//
//    return quadUniformsArray
//  }
  
  func makeAdaptiveGrid(dEye: SIMD3<Double>, side: Side) -> [QuadUniforms] {
    let modelSize: Double = 2.0
    var modelOrigin: SIMD3<Double>
    let worldOrigin: SIMD3<Double>
    switch side {
    case .top:
      modelOrigin = SIMD3<Double>(Double(-1), Double(1), Double(-1))
//    case .front:
//      origin = SIMD3<Double>(Double(1), Double(-1), Double(-1))
//    case .left:
//      origin = SIMD3<Double>(Double(-1), Double(-1), Double(1))
//    case .bottom:
//      origin = SIMD3<Double>(Double(-1), Double(-1), Double(-1))
//    case .back:
//      origin = SIMD3<Double>(Double(-1), Double(-1), Double(-1))
//    case .right:
//      origin = SIMD3<Double>(Double(-1), Double(-1), Double(-1))
    }
    worldOrigin = modelOrigin * dRadius
    
    return makeTieredLod(worldEye: dEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize)

//    return makeAdaptiveLod(eye: dEye, corner: modelOrigin, cubeOrigin: worldOrigin, size: modelSize, side: side)
  }

  func makeTieredLod(worldEye: SIMD3<Double>, worldOrigin: SIMD3<Double>, modelOrigin: SIMD3<Double>, modelSize: Double) -> [QuadUniforms] {
    [
//      makeTieredLod(scale: 1, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 2, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 4, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 8, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 16, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
      makeTieredLod(scale: 32, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 64, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 128, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 256, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 512, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
      makeTieredLod(scale: 1024, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 2048, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
//      makeTieredLod(scale: 4096, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
      makeTieredLod(scale: 8192, worldEye: worldEye, worldOrigin: worldOrigin, modelOrigin: modelOrigin, modelSize: modelSize),
    ]
  }
  
  func makeTieredLod(scale: Double, worldEye: SIMD3<Double>, worldOrigin: SIMD3<Double>, modelOrigin: SIMD3<Double>, modelSize: Double) -> QuadUniforms {
    let distantModelSize = modelSize / 1.0
    let distant = makeQuad(worldOrigin: worldOrigin, worldSize: dRadius*distantModelSize, modelOrigin: modelOrigin, modelSize: distantModelSize)
    
    let dist: Double = worldEye.y - dRadius
    let pDist: Double = dist / dRadius
    let cDist: Double = simd_clamp(pDist, 0.0, 1.0)
    let ncDist: Double = 1.0 + (1.0 - cDist)
    let closeScale = scale//512.0//trunc(log2(ncDist * 8))
    print(closeScale)
    let eyeCloseScale = dRadius / closeScale / 4.0
    var eyeOrigin = SIMD3<Double>(dEye.x, 0, dEye.z)
    let truncEyeOrigin = SIMD3<Int>(eyeOrigin / eyeCloseScale)
    let eyeScale = eyeCloseScale / dRadius
    eyeOrigin = SIMD3<Double>(Double(truncEyeOrigin.x) * eyeScale, Double(truncEyeOrigin.y) * eyeScale, Double(truncEyeOrigin.z) * eyeScale)
    
    let closeModelSize = modelSize / closeScale
    let closeModelOrigin = eyeOrigin - (SIMD3<Double>(closeModelSize, 0, closeModelSize) / 2) + SIMD3<Double>(0, modelOrigin.y, 0)
    let closeWorldOrigin = closeModelOrigin * dRadius// - (SIMD3<Double>(-1, 0, -1) * dRadius)
    let close = makeQuad(worldOrigin: closeWorldOrigin, worldSize: dRadius*closeModelSize, modelOrigin: closeModelOrigin, modelSize: closeModelSize)
    
    return close
  }

  func makeAdaptiveLod(eye: SIMD3<Double>, corner: SIMD3<Double>, cubeOrigin: SIMD3<Double>, size: Double, side: Side) -> [QuadUniforms] {
    let threshold: Double = Double(size*dRadius*thresholdFactor)
    let half = size / 2
    let dHalf = Double(half)
    let center = corner + dHalf
//    let surfaceCenter = normalize(center) * Double(iRadius)
    let surfaceCenter = center * dRadius
    let d = distance(SIMD3<Double>(eye.x, dRadius, eye.z), surfaceCenter)
    if size < 0.0001 || d > threshold {
      return [makeQuad(worldOrigin: cubeOrigin, worldSize: dRadius*size, modelOrigin: corner, modelSize: size)]
    }
    let q1d: simd_double3
    let q2d: simd_double3
    let q3d: simd_double3
    switch side {
    case .top://, .bottom:
      q1d = simd_double3(dHalf, 0, 0)
      q2d = simd_double3(0, 0, dHalf)
      q3d = simd_double3(dHalf, 0, dHalf)
//    case .front, .back:
//      q1d = simd_double3(0, dHalf, 0)
//      q2d = simd_double3(0, 0, dHalf)
//      q3d = simd_double3(0, dHalf, dHalf)
//    case .left, .right:
//      q1d = simd_double3(dHalf, 0, 0)
//      q2d = simd_double3(0, dHalf, 0)
//      q3d = simd_double3(dHalf, dHalf, 0)
    }
    let q0 = makeAdaptiveLod(eye: eye, corner: corner, cubeOrigin: cubeOrigin, size: half, side: side)
    let q1 = makeAdaptiveLod(eye: eye, corner: corner + q1d, cubeOrigin: cubeOrigin + q1d*dRadius, size: half, side: side)
    let q2 = makeAdaptiveLod(eye: eye, corner: corner + q2d, cubeOrigin: cubeOrigin + q2d*dRadius, size: half, side: side)
    let q3 = makeAdaptiveLod(eye: eye, corner: corner + q3d, cubeOrigin: cubeOrigin + q3d*dRadius, size: half, side: side)
    return q0 + q1 + q2 + q3
  }

  func makeQuad(worldOrigin: SIMD3<Double>, worldSize: Double, modelOrigin: SIMD3<Double>, modelSize: Double) -> QuadUniforms {
    let iCubeOrigin: vector_int3 = SIMD3<Int32>(Int32(floor(worldOrigin.x)), Int32(floor(worldOrigin.y)), Int32(floor(worldOrigin.z)))
    let m = double4x4(scaleBy: dRadius/dLod) * double4x4(translationBy: SIMD3<Double>(modelOrigin)) * double4x4(scaleBy: modelSize)
    let mvp = vp * m
    let mv = simd_float4x4(viewMatrix * m)
    let wp: simd_float3 = (mv * SIMD4<Float>(0.5, 0, 0.5, 1)).xyz
    let wpd = distance(fEye, wp)
    let t: Int32 = 64//Int32(63 * (1 - simd_smoothstep(0, 1000, wpd))) + 1
    let quadUniforms = QuadUniforms(m: float4x4(m), mvp: float4x4(mvp), scale: Float(modelSize), cubeOrigin: iCubeOrigin, cubeSize: Int32(floor(worldSize)), tessellation: (t, t, t, t))
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
        points.append([left, bottom])
        points.append([right, bottom])
        points.append([right, top])
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
    vertexDescriptor.attributes[0].format = .float2
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    descriptor.vertexDescriptor = vertexDescriptor
    
    descriptor.tessellationFactorStepFunction = .perPatch
    descriptor.maxTessellationFactor = 64
    descriptor.tessellationPartitionMode = .pow2
    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: descriptor)!
  }
}
