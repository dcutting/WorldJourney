import MetalKit
import PhyKit

final class Renderer: NSObject, MTKViewDelegate {
  var diagnosticMode: Int32 = 0

  private let iRadius: Int32 = 36 * Int32(pow(2.0, 17.0))  // For face edges to line up with mesh, must be of size: 36 * 2^y
  private var dAmplitude: Double = 8_000
  private let kph: Double = 10000
  private var mps: Double { kph * 1000.0 / 60.0 / 60.0 }
  private lazy var fov: Double = calculateFieldOfView(degrees: 48)
  private let backgroundColour = MTLClearColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1)
  private var nearZ: Double { 10 }
  private var farZ: Double { dAltitude + 3 * dRadius }
  private var baseRingLevel: Int32 = 1
  private let maximumRingLevel: Int32 = 19
  private var lastGPUEndTime: CFTimeInterval = 0

  private var dStartTime: Double = 0
  private var dTime: Double = 0
  private var dEye: simd_double3 {
    get {
      simd_double3(physics.avatar.position.simd)
    }
    set {
      physics.halt()
      physics.avatar.position = simd_float3(newValue).phyVector3
    }
  }
  private let dSun = simd_double3(repeating: 105_781_668_823)

  private var dRadius: Double { Double(iRadius) }
  private var dAltitude: Double { dEye.y }
  private var fRadius: Float { Float(iRadius) }
  private var fAmplitude: Float { Float(dAmplitude) }
  private var fTime: Float { Float(dTime) }
  private var ringCenterPosition: simd_double3 { simd_double3(dEye.x, 0, dEye.z) }
  private var ringCenterEyeOffset: simd_float3 { simd_float3(ringCenterPosition - dEye) }
  private var iRingCenterCell: simd_int2 { simd_int2(dEye.xz) }
  private var fEye: simd_float3 { simd_float3(dEye) }
  private var fSun: simd_float3 { simd_float3(dSun) }

  private let physics = Physics(planetMass: 6e16, moveAmount: 200000, gravity: false)

  func adjust(heightM: Double) {
    dEye.y = heightM
  }
  
  private func reset() {
    dStartTime = CACurrentMediaTime()
    dEye = simd_double3(1000, 20000, 1000)
  }
  
  private func gameLoop(screenWidth: Double, screenHeight: Double) -> Uniforms {
    readInput()
    updateClock()
    updateLod()
    printStats()

    let uniforms = Uniforms(
      mvp: makeMVP(width: screenWidth, height: screenHeight),
      eye: fEye,
      sun: fSun,
      ringCenterEyeOffset: ringCenterEyeOffset,
      ringCenterCell: iRingCenterCell,
      baseRingLevel: baseRingLevel,
      maxRingLevel: maximumRingLevel,
      radius: iRadius,
      amplitude: fAmplitude,
      time: fTime,
      diagnosticMode: diagnosticMode
    )
    return uniforms
  }

  private func readInput() {
    // Craft control.

    // Translation.
    if Keyboard.IsKeyPressed(KeyCodes.w) {
      physics.forward()
    }
    if Keyboard.IsKeyPressed(KeyCodes.s) {
      physics.back()
    }
    if Keyboard.IsKeyPressed(KeyCodes.a) {
      physics.strafeLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.d) {
      physics.strafeRight()
    }
    if Keyboard.IsKeyPressed(KeyCodes.e) {
      physics.strafeUp()
    }
    if Keyboard.IsKeyPressed(KeyCodes.q) {
      physics.strafeDown()
    }
    // Attitude.
    if Keyboard.IsKeyPressed(KeyCodes.j) {
      physics.turnLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.l) {
      physics.turnRight()
    }
    if Keyboard.IsKeyPressed(KeyCodes.i) {
      physics.turnDown()
    }
    if Keyboard.IsKeyPressed(KeyCodes.k) {
      physics.turnUp()
    }
    if Keyboard.IsKeyPressed(KeyCodes.u) {
      physics.rollLeft()
    }
    if Keyboard.IsKeyPressed(KeyCodes.o) {
      physics.rollRight()
    }
    // Boost.
    if Keyboard.IsKeyPressed(KeyCodes.space) {
      physics.strafeUp()
    }
    if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
      physics.halt()
    }

    // Locations.
    if Keyboard.IsKeyPressed(KeyCodes.z) {
      dEye = simd_double3(1000, 100, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
      dEye = simd_double3(1000, 1000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.c) {
      dEye = simd_double3(1000, 3000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.c) {
      dEye = simd_double3(1000, 6000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.f) {
      dEye = simd_double3(1000, 12000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.v) {
      dEye = simd_double3(1000, 60000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.g) {
      dEye = simd_double3(1000, 120000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      dEye = simd_double3(1000, 60000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.h) {
      dEye = simd_double3(1000, 1200000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.n) {
      dEye = simd_double3(1000, 6000000, 1000)
    }
    if Keyboard.IsKeyPressed(KeyCodes.m) {
      dEye = simd_double3(1000, 12000000, 1000)
    }

    // Diagnostic modes.
    if Keyboard.IsKeyPressed(KeyCodes.zero) {
      diagnosticMode = 0
    }
    if Keyboard.IsKeyPressed(KeyCodes.one) {
      diagnosticMode = 1
    }
    if Keyboard.IsKeyPressed(KeyCodes.two) {
      diagnosticMode = 2
    }
    if Keyboard.IsKeyPressed(KeyCodes.three) {
      diagnosticMode = 3
    }
    if Keyboard.IsKeyPressed(KeyCodes.four) {
      diagnosticMode = 4
    }
    if Keyboard.IsKeyPressed(KeyCodes.five) {
      diagnosticMode = 5
    }
  }

  private func updateClock() {
    dTime = CACurrentMediaTime() - dStartTime
  }
  
  private func updateLod() {
    let msl = max(1, dAltitude)
    let ring = Int32(floor(log2(msl / 1000))) + 4 // TODO: how to find base ring level? This is based on sea level, but should be based on calculated terrain height.
    baseRingLevel = max(1, min(ring, maximumRingLevel))
  }
  
  private var numRings: Int32 {
    maximumRingLevel - baseRingLevel + 1
  }

  private func makeMVP(width: Double, height: Double) -> float4x4 {
    let viewMatrix = physics.avatar.transform.simd.inverse
    let perspectiveMatrix = double4x4(perspectiveProjectionFov: fov, aspectRatio: width / height, nearZ: nearZ, farZ: farZ)
    let mvp = float4x4(perspectiveMatrix) * viewMatrix;
    return mvp
  }
  
  private func printStats() {
//    let ringCenterCellString = String(format: "(%d, %d)", iRingCenterCell.x, iRingCenterCell.y)
    let eyeString = String(format: "(%.2f, %.2f, %.2f)", dEye.x, dEye.y, dEye.z)
//    let coreString = String(format: "%.2fkm", dEye.y / 1000.0)
    let altitudeString = abs(dAltitude) < 1000.0 ? String(format: "%.1fm", dAltitude) : String(format: "%.2fkm", dAltitude / 1000.0)
    let velocity = length(physics.avatar.linearVelocity.simd)
    let speedString = velocity.isFinite ? String(format: "%.1fkm/h", velocity * 3.6) : "N/A"
    let timeString = String(format: "%.2fs", dTime)
    print(
      timeString,
      " Ring:", baseRingLevel,
//      " Cell:", ringCenterCellString,
      " Eye:", eyeString,
//      " Core:", coreString,
      " MSL:", altitudeString,
      " Speed:", speedString,
//      " nearZ:", nearZ,
//      " farZ:", farZ
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
    }
    if let drawable = view.currentDrawable {
      commandBuffer.present(drawable)
    }
    commandBuffer.addCompletedHandler { buffer in
      self.lastGPUEndTime = buffer.gpuEndTime
    }
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    physics.step(time: self.lastGPUEndTime)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
