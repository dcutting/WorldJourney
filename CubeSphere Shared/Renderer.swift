import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
  var overheadView = true
  var diagnosticMode = true

  private let iRadius: Int32 = 6_371_000
  private let dAmplitude: Double = 848
  private let kph: Double = 200
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
  private var fRadius: Float { Float(iRadius) }
  private var fRadiusLod: Float { Float(dRadius / dLod) }
  private var fAmplitudeLod: Float { Float(dAmplitude / dLod) }
  private var fTime: Float { Float(dTime) }
  private var fLod: Float { Float(dLod) }
  private var iEyeCell: simd_int3 { simd_int3(floor(dEye)) }
  private var dEyeLod: simd_double3 { dEye / dLod }
  private var dSunLod: simd_double3 { dSun / dLod }
  private var fEyeLod: simd_float3 { simd_float3(dEyeLod) }
  private var fSunLod: simd_float3 { simd_float3(dSunLod) }
  private var numRings: Int32 { min(6, maximumRingLevel - baseRingLevel + 1) }

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
      eyeCell: iEyeCell,
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
    let mps = kph * 1000.0 / 60.0 / 60.0
    let distance =  dTime * mps
//    let altitude = max(dAmplitude/2.0, 3 * dAmplitude - 2000 * log(dTime))
    let altitude = max(dAmplitude/4.0, dAmplitude * 10000.0 + dAmplitude * 10000 * cos(-dTime / 8))
//    let altitude = 4000.0// 50000.0
    dEye = simd_double3(2 * distance, dRadius + altitude, 10000 + 3 * distance)
  }
  
  private func makeMVP(width: Double, height: Double) -> double4x4 {
    let atLod = simd_double3(0, 0, 0) / dLod
    let up = simd_double3(0, 1, 0)
    let viewMatrix = look(at: atLod, eye: dEyeLod, up: up)
    let perspectiveMatrix = makeProjectionMatrix(w: width, h: height, fov: fov, farZ: farZ)
    let mvp = perspectiveMatrix * viewMatrix;
    return mvp
  }
  
  private func updateLod() {
    let dist = length(dEye)
    dLod = floor(dist/dLodFactor)
    
    let msl = max(1, dEye.y - dRadius)
    let ring = Int32(floor(log2(msl))) - 8
    baseRingLevel = max(1, min(ring, maximumRingLevel))
  }
  
  private func printStats() {
    let amplitudeString = String(format: "%.2f", fAmplitudeLod)
//    let eyeCellString = String(format: "(%ld, %ld, %ld)", iEyeCell.x, iEyeCell.y, iEyeCell.z)
    let eyeString = String(format: "(%.2f, %.2f, %.2f)", dEye.x, dEye.y, dEye.z)
    let coreString = String(format: "%.2fkm", length(dEye) / 1000.0)
    let altitudeM = dEye.y - dRadius
    let altitudeString = abs(altitudeM) < 1000.0 ? String(format: "%.1fm", altitudeM) : String(format: "%.2fkm", altitudeM / 1000.0)
    let timeString = String(format: "%.2fs", dTime)
    print(
      timeString,
      " LOD:", dLod,
      " ALOD:", amplitudeString,
      " Ring:", baseRingLevel,
//      " Cell:", eyeCellString,
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
