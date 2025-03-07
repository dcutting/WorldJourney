import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
  var diagnosticMode = false

  private let iRadius: Int32 = 36 * Int32(pow(2.0, 17.0))  // For face edges to line up with mesh, must be of size: 36 * 2^y
  private let dAmplitude: Double = 4_000
  private let kph: Double = 10000
  private var mps: Double { kph * 1000.0 / 60.0 / 60.0 }
  private lazy var fov: Double = calculateFieldOfView(degrees: 48)
  private let backgroundColour = MTLClearColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1)
  private let dLodFactor: Double = 100
  private var nearZ: Double { 10 }
  private var farZ: Double { dAltitude + 3 * dRadius }
  private var baseRingLevel: Int32 = 1
  private let maximumRingLevel: Int32 = 19
  
  private var dStartTime: Double = 0
  private var dTime: Double = 0
  private var dLod: Double = 1
  private var dEye: simd_double3 = .zero
  private let dSun = simd_double3(repeating: 105_781_668_823)

  private var dRadius: Double { Double(iRadius) }
  private var dAltitude: Double { dEye.y }
  private var fRadius: Float { Float(iRadius) }
  private var fRadiusLod: Float { Float(dRadius / dLod) }
  private var fAmplitudeLod: Float { Float(dAmplitude / dLod) }
  private var fTime: Float { Float(dTime) }
  private var fLod: Float { Float(dLod) }
  private var ringCenterPosition: simd_double3 { simd_double3(dEye.x, 0, dEye.z) }
  private var ringCenterEyeOffset: simd_double3 { ringCenterPosition - dEye }
  private var ringCenterEyeOffsetLod: simd_float3 { simd_float3(ringCenterEyeOffset / dLod) }
  private var iRingCenterCell: simd_int2 { simd_int2(dEye.xz) }
  private var dEyeLod: simd_double3 { dEye / dLod }
  private var dSunLod: simd_double3 { dSun / dLod }
  private var fEyeLod: simd_float3 { simd_float3(dEyeLod) }
  private var fSunLod: simd_float3 { simd_float3(dSunLod) }
  private var nearZLod: Double { nearZ / dLod }
  private var farZLod: Double { farZ / dLod }

  func adjust(heightM: Double) {
    dEye.y = heightM
  }
  
  private func reset() {
    dStartTime = CACurrentMediaTime()
    dEye = simd_double3(20000, 20000, 20000)
  }
  
  private func gameLoop(screenWidth: Double, screenHeight: Double) -> Uniforms {
    readInput()
    updateClock()
//    updateWorld()
    updateLod()
    printStats()

    let uniforms = Uniforms(
      mvp: simd_float4x4(makeMVP(width: screenWidth, height: screenHeight)),
      lod: fLod,
      eyeLod: fEyeLod,
      sunLod: fSunLod,
      ringCenterEyeOffsetLod: ringCenterEyeOffsetLod,
      ringCenterCell: iRingCenterCell,
      baseRingLevel: baseRingLevel,
      maxRingLevel: maximumRingLevel,
      radius: iRadius,
      radiusLod: fRadiusLod,
      amplitudeLod: fAmplitudeLod,
      time: fTime,
      diagnosticMode: diagnosticMode
    )
    return uniforms
  }

  private func readInput() {
    var speed = 100.0
    if Keyboard.IsKeyPressed(.shift) {
      speed *= 10.0
    }
    if Keyboard.IsKeyPressed(KeyCodes.w) {
      dEye.z -= speed
    }
    if Keyboard.IsKeyPressed(KeyCodes.s) {
      dEye.z += speed
    }
    if Keyboard.IsKeyPressed(KeyCodes.a) {
      dEye.x -= speed
    }
    if Keyboard.IsKeyPressed(KeyCodes.d) {
      dEye.x += speed
    }
    if Keyboard.IsKeyPressed(KeyCodes.q) {
      dEye.y += speed
    }
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      dEye.y -= speed
    }
  }

  private func updateClock() {
    dTime = CACurrentMediaTime() - dStartTime
  }
  
  private func updateWorld() {
    let distance =  dTime * mps
    let base: Double = dAmplitude * 4.9
    let top = dRadius * 1//0.5
    let altitude = base// + ((top - base) * max(0, sin(-dTime * 0.05) * 0.5 + 0.2))
    let x: Double = dRadius - distance// + 2000.31397 * cos(distance * 0.0005)
    let y: Double = altitude
    let z: Double = dRadius + 20000//-dRadius + 5.4314 * distance
    dEye = simd_double3(x, y, z)
  }

  private func updateLod() {
    dLod = 1.0
    
    let msl = max(1, dAltitude)
    let ring = Int32(floor(log2(msl / 1000))) + 4 // TODO: how to find base ring level?
    baseRingLevel = max(1, min(ring, maximumRingLevel))
  }
  
  private var numRings: Int32 {
    maximumRingLevel - baseRingLevel + 1
  }

  private func makeMVP(width: Double, height: Double) -> double4x4 {
    let at = simd_double3(dEye.x, 0, 0)
    let up = simd_double3(0, 1, 0)

    let atLod = (at - dEye) / dLod
    let viewMatrix = look(at: atLod, eye: .zero, up: up)
    let perspectiveMatrix = double4x4(perspectiveProjectionFov: fov, aspectRatio: width / height, nearZ: nearZLod, farZ: farZLod)
    let mvp = perspectiveMatrix * viewMatrix;
    return mvp
  }
  
  private func printStats() {
    let ringCenterCellString = String(format: "(%ld, %ld)", iRingCenterCell.x, iRingCenterCell.y)
    let eyeString = String(format: "(%.2f, %.2f, %.2f)", dEye.x, dEye.y, dEye.z)
    let coreString = String(format: "%.2fkm", dEye.y / 1000.0)
    let altitudeString = abs(dAltitude) < 1000.0 ? String(format: "%.1fm", dAltitude) : String(format: "%.2fkm", dAltitude / 1000.0)
    let timeString = String(format: "%.2fs", dTime)
    print(
      timeString,
      " LOD:", dLod,
      " Ring:", baseRingLevel,
      " Cell:", ringCenterCellString,
      " Eye:", eyeString,
      " Core:", coreString,
      " MSL:", altitudeString,
      " nearZ:", nearZ,
      " farZ:", farZ
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
      metalKitView.preferredFramesPerSecond = 200

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
