import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
  var overheadView = true
  var diagnosticMode = true

  private let iRadius: Int32 = 4_718_592  // For face edges to line up with mesh, must be of size: 36 * 2^y
  private let dAmplitude: Double = 1000//8_848
  private let kph: Double = 500
  private var mps: Double { kph * 1000.0 / 60.0 / 60.0 }
  private lazy var fov: Double = calculateFieldOfView(degrees: 48)
  private let backgroundColour = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
  private let dLodFactor: Double = 100
  private let farZ: Double = 1000
  private var baseRingLevel: Int32 = 1
  private let maximumRingLevel: Int32 = 22
  
  private var dStartTime: Double = 0
  private var dTime: Double = 0
  private var dLod: Double = 1
  private var dEye: simd_double3 = .zero
  private var dSun: simd_double3 = .zero

  private var dRadius: Double { Double(iRadius) }
  private var dAltitude: Double { length(dEye) - dRadius }
  private var fRadius: Float { Float(iRadius) }
  private var fRadiusLod: Float { Float(dRadius / dLod) }
  private var fAmplitudeLod: Float { Float(dAmplitude / dLod) }
  private var fTime: Float { Float(dTime) }
  private var fLod: Float { Float(dLod) }
  private var ringCenterPositionLod: simd_float2 { simd_float2(dEye.xz * (dRadius / dEye.y) / dLod) }
  private var iRingCenterCell: simd_int2 { simd_int2(dEye.xz * (dRadius / dEye.y)) }
  private var dEyeLod: simd_double3 { dEye / dLod }
  private var dSunLod: simd_double3 { dSun / dLod }
  private var fEyeLod: simd_float3 { simd_float3(dEyeLod) }
  private var fSunLod: simd_float3 { simd_float3(dSunLod) }

  func adjust(heightM: Double) {
    dEye.y = dRadius + heightM
  }
  
  private func reset() {
    dStartTime = CACurrentMediaTime()
    dEye = .zero
    dSun = simd_double3(repeating: 105_781_668_823)
  }
  
  private func gameLoop(screenWidth: Double, screenHeight: Double) -> Uniforms {
    updateClock()
    updateWorld()
    updateLod()
    printStats()

    let uniforms = Uniforms(
      mvp: simd_float4x4(makeMVP(width: screenWidth, height: screenHeight)),
      lod: fLod,
      eyeLod: fEyeLod,
      sunLod: fSunLod,
      ringCenterPositionLod: ringCenterPositionLod,
      ringCenterCell: iRingCenterCell,
      baseRingLevel: baseRingLevel,
      radius: iRadius,
      radiusLod: fRadiusLod,
      amplitudeLod: fAmplitudeLod,
      time: fTime,
      diagnosticMode: diagnosticMode
    )
    return uniforms
  }

  private func updateClock() {
    dTime = CACurrentMediaTime() - dStartTime
  }
  
  private func updateWorld() {
    let distance =  dTime * mps
//    let altitude = max(dAmplitude/8.0, dAmplitude - 1000 * log(dTime * 2000))
//    let altitude = max(dAmplitude/4.0, dAmplitude * 10000.0 + dAmplitude * 10000 * cos(-dTime / 8))
    let base = 4.0 * dAmplitude
    let top = 4.0 * dRadius
    let altitude = base + ((top - base) * max(0, (sin(dTime * 0.4) * 0.5 + 0.2)))
//    let x = (cos(dTime * 0.01) + sin(dTime * 0.005)) * 1_000_000
//    let z = (sin(dTime * 0.02) - cos(dTime * 0.005)) * 1_000_000
    let x = /*dRadius*/ -2.31397*distance
    let y = dRadius + altitude
    let z = /*dRadius*/ -1.124211*distance
    dEye = simd_double3(x, dRadius, z)
    dEye = normalize(dEye) * y
  }
  
  private func updateLod() {
    dLod = floor(dAltitude/dLodFactor)
    
    let msl = max(1, dAltitude)
    let ring = Int32(floor(log2(msl))) - 6
    baseRingLevel = max(1, min(ring, maximumRingLevel))
  }
  
  private var numRings: Int32 {
    min(6, maximumRingLevel - baseRingLevel + 1)
  }

  private func makeMVP(width: Double, height: Double) -> double4x4 {
//    let at = simd_double3(dEye.x, 0, dEye.z) + dEye
//    let up = simd_double3(0, 0, -1)
//    let viewMatrix = look(at: at / dLod, eye: .zero, up: up)
    let at = simd_double3.zero
    let up = simd_double3(0, 0, -1)

    let atLod = at / dLod
    let viewMatrix = look(at: atLod, eye: dEyeLod, up: up)
    let perspectiveMatrix = makeProjectionMatrix(w: width, h: height, fov: fov, farZ: farZ)
    let mvp = perspectiveMatrix * viewMatrix;
    return mvp
  }
  
  private func printStats() {
    let ringCenterCellString = String(format: "(%ld, %ld)", iRingCenterCell.x, iRingCenterCell.y)
    let eyeString = String(format: "(%.2f, %.2f, %.2f)", dEye.x, dEye.y, dEye.z)
    let coreString = String(format: "%.2fkm", length(dEye) / 1000.0)
    let altitudeString = abs(dAltitude) < 1000.0 ? String(format: "%.1fm", dAltitude) : String(format: "%.2fkm", dAltitude / 1000.0)
    let timeString = String(format: "%.2fs", dTime)
    print(
      timeString,
      " LOD:", dLod,
      " Ring:", baseRingLevel,
      " Cell:", ringCenterCellString,
      " Eye:", eyeString,
      " Core:", coreString,
      " MSL:", altitudeString
    )
  }
  
  // MARK: - boilerplate
  
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState

  init?(metalKitView: MTKView) {
    do {
      self.device = metalKitView.device!
      guard let queue = self.device.makeCommandQueue() else { return nil }
      self.commandQueue = queue
      metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
      metalKitView.colorPixelFormat = .bgra8Unorm_srgb
      metalKitView.sampleCount = 1
      metalKitView.clearColor = backgroundColour
      
      let library = self.device.makeDefaultLibrary()
      let pipelineDescriptor = MTLMeshRenderPipelineDescriptor()
      pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
      pipelineDescriptor.objectFunction = library?.makeFunction(name: "terrainObject")
      pipelineDescriptor.meshFunction = library?.makeFunction(name: "terrainMesh")
      pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "terrainFragment")
      pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
      pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
      pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
      let (pipeline, _) = try self.device.makeRenderPipelineState(descriptor: pipelineDescriptor, options: [])
      self.pipelineState = pipeline
      let depthStateDescriptor = MTLDepthStencilDescriptor()
      depthStateDescriptor.depthCompareFunction = .less
      depthStateDescriptor.isDepthWriteEnabled = true
      guard let depthState = self.device.makeDepthStencilState(descriptor: depthStateDescriptor) else { return nil }
      self.depthState = depthState
    } catch {
      print(error)
      return nil
    }
    super.init()
    reset()
  }
  
  func draw(in view: MTKView) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
    if let renderPassDescriptor = view.currentRenderPassDescriptor,
       let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
      var uniforms = gameLoop(screenWidth: view.bounds.width, screenHeight: view.bounds.height)
      renderEncoder.setRenderPipelineState(pipelineState)
      renderEncoder.setDepthStencilState(depthState)
      renderEncoder.setObjectBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      let cells = 4 // this must be 4
      let oGroups = MTLSize(width: cells, height: cells, depth: Int(numRings))  // How many objects to make. No real limit.
      let oThreadsPerGroup = MTLSize(width: 1, height: 1, depth: 1)             // How to divide up the objects into work units.
      let mThreadsPerMesh = MTLSize(width: 1, height: 1, depth: 1)              // How many threads to work on each mesh.
      renderEncoder.drawMeshThreadgroups(
        oGroups,
        threadsPerObjectThreadgroup: oThreadsPerGroup,
        threadsPerMeshThreadgroup: mThreadsPerMesh
      )
      renderEncoder.endEncoding()
      if let drawable = view.currentDrawable {
        commandBuffer.present(drawable)
      }
    }
    commandBuffer.commit()
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
