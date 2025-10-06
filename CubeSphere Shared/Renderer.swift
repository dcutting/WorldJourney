import MetalKit
import PhyKit

final class Renderer: NSObject, MTKViewDelegate {
  // For face edges to line up with mesh, iRadius must be of size: 36 * 2^y.
  private static let iRadiusExponent: Int32 = 17
  private let iRadiusW: Int32 = 36 * Int32(pow(2.0, Double(iRadiusExponent)))
  private static let sunDistance = 105_781_668_823.0
  private var dSunW = simd_double3(repeating: sunDistance)
  private let sunSpeed = 1.0
  private let backgroundColour = MTLClearColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1)
  private var nearZ: Double { 0.5 }
  private var farZ: Double { dAltitudeW + 3 * dRadiusW }
  private lazy var fov: Double = calculateFieldOfView(degrees: 48)

  private var diagnosticMode: Int32 = 4
  private var mappingMode: Int32 = 0 // 0 == sphere, 1 == cube
  private var baseRingLevel: Int32 = 1
  private let maximumRingLevel: Int32 = iRadiusExponent + 1
  private var lastGPUEndTime: CFTimeInterval = 0
  private var dStartTime: Double = 0
  private var dTime: Double = 0
  private var dEyeW: simd_double3 {
    get {
      physics.avatar.position.simd
    }
    set {
      physics.halt()
      physics.avatar.position = newValue.phyVector3
    }
  }

  private var dRadiusW: Double { Double(iRadiusW) }
  private var fRadiusW: Float { Float(iRadiusW) }
  private var dAltitudeW: Double { mappingMode == 0 ? length(dEyeW) - dRadiusW : dEyeW.y - dRadiusW }
  private var fTime: Float { Float(dTime) }
  private var iRingCenterW: simd_int2 { mappingMode == 0 ? simd_int2((dEyeW * dRadiusW / dEyeW.y).xz) : iEyeW.xz }
  private var fEyeW: simd_float3 { simd_float3(dEyeW) }
  private var iEyeW: simd_int3 { simd_int3(dEyeW) }
  private var fSunlightDirectionW: simd_float3 { simd_float3(normalize(-dSunW)) }

  private let physics = Physics(planetMass: 6e16, gravity: false, moveAmount: 200, turnAmount: 10)

  private func reset() {
    dStartTime = CACurrentMediaTime()
    dEyeW = simd_double3(0, dRadiusW + 1000, 0)
    physics.avatar.eulerOrientation = .init(x: -3.1415/2.0, y: 0, z: 0)
  }
  
  private func gameLoop(screenWidth: Double, screenHeight: Double) -> Uniforms {
    readInput()
    updateClock()
//    updateSun()
    updateRingLevel()
    printStats()

    let uniforms = Uniforms(
      mvp: makeMVP(width: screenWidth, height: screenHeight),
      fEyeW: fEyeW,
      fSunlightDirectionW: fSunlightDirectionW,
      iRingCenterW: iRingCenterW,
      iEyeW: iEyeW,
      iRadiusW: iRadiusW,
      baseRingLevel: baseRingLevel,
      maxRingLevel: maximumRingLevel,
      fTime: fTime,
      diagnosticMode: diagnosticMode,
      mappingMode: mappingMode
    )
    return uniforms
  }

  private func updateClock() {
    dTime = CACurrentMediaTime() - dStartTime
  }
  
  private func updateSun() {
    dSunW = SIMD3<Double>(cos(dTime * sunSpeed), 1, sin(dTime * sunSpeed)) * Self.sunDistance
  }

  private func updateRingLevel() {
    // TODO: how to find base ring level? This is based on sea level, but should be based on calculated terrain height.
    let msl = max(1, dAltitudeW)
    let ring = Int32(floor(log2(msl / 1000))) + 4 // TODO: this ain't right.
    baseRingLevel = 1//max(1, min(ring, maximumRingLevel))
  }
  
  private var numRings: Int32 {
    maximumRingLevel - baseRingLevel + 1
  }

  private func makeMVP(width: Double, height: Double) -> float4x4 {
    // The translation is needed to smoothly move within a single 1x1m cell.
    let offset = simd_fract(simd_abs(dEyeW)) * simd_sign(dEyeW)
    let translate = simd_double4x4(translationBy: -offset)
    let viewMatrix = physics.avatar.orientation.transform.simd.inverse * translate
    let perspectiveMatrix = double4x4(perspectiveProjectionFov: fov, aspectRatio: width / height, nearZ: nearZ, farZ: farZ)
    let mvp = float4x4(perspectiveMatrix * viewMatrix);
    return mvp
  }
  
  private func printStats() {
    let radiusString = String(format: "%.3fkm", dRadiusW / 1000.0)
    let eyeString = String(format: "(%.2f, %.2f, %.2f)m", dEyeW.x, dEyeW.y, dEyeW.z)
    let altitudeString = abs(dAltitudeW) < 1000.0 ? String(format: "%.2fm", dAltitudeW) : String(format: "%.5fkm", dAltitudeW / 1000.0)
    let velocity = length(physics.avatar.linearVelocity.simd)
    let speedString = velocity.isFinite ? String(format: "%.1fkm/h", velocity * 3.6) : "N/A"
    let timeString = String(format: "%.2fs", dTime)
    print(
      timeString,
      " Radius:" , radiusString,
      " Ring:", baseRingLevel,
      " Eye:", eyeString,
      " MSL:", altitudeString,
      " Speed:", speedString
    )
  }
  
  private func readInput() {
    var heightMultiplier = 1.0

    // Craft control.

    if Keyboard.IsKeyPressed(.shift) {
      physics.moveMultiplier = 1
      physics.turnMultiplier = 1
    } else {
      physics.moveMultiplier = 1000
      physics.turnMultiplier = 10
      heightMultiplier = 2.0
    }

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

    if Keyboard.IsKeyPressed(KeyCodes.r) {
      setSurfacePosition(x: -dRadiusW * 0.95, z: -dRadiusW * 0.92)
    }
    if Keyboard.IsKeyPressed(KeyCodes.t) {
      setSurfacePosition(x: dRadiusW * 0.98, z: -dRadiusW * 0.91)
    }
    if Keyboard.IsKeyPressed(KeyCodes.f) {
      setSurfacePosition(x: -dRadiusW * 0.97, z: dRadiusW * 0.96)
    }
    if Keyboard.IsKeyPressed(KeyCodes.g) {
      setSurfacePosition(x: dRadiusW * 0.9, z: dRadiusW * 0.99)
    }
    if Keyboard.IsKeyPressed(KeyCodes.y) {
      setSurfacePosition(x: 300, z: 500)
    }

    // Height.

    if Keyboard.IsKeyPressed(KeyCodes.z) {
      set(altitude: 128 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.x) {
      set(altitude: 512 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.c) {
      set(altitude: 2_048 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.v) {
      set(altitude: 8_192 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.b) {
      set(altitude: 32_768 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.h) {
      set(altitude: 131_072 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.n) {
      set(altitude: 524_288 * heightMultiplier)
    }
    if Keyboard.IsKeyPressed(KeyCodes.m) {
      set(altitude: 2_097_152 * heightMultiplier)
    }

    // Diagnostic modes.
    if Keyboard.IsKeyPressed(KeyCodes.nine) {
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

    // Mapping modes.
    if Keyboard.IsKeyPressed(KeyCodes.zero) {
      mappingMode = 0
    }
    if Keyboard.IsKeyPressed(KeyCodes.p) {
      mappingMode = 1
    }
  }

  func set(altitude: Double) {
    if mappingMode == 0 {
      dEyeW = normalize(dEyeW) * (altitude + dRadiusW)
    } else {
      dEyeW.y = altitude + dRadiusW
    }
  }

  func setSurfacePosition(x: Double, z: Double) {
    if mappingMode == 0 {
      let p = SIMD3<Double>(x, dRadiusW, z)
      dEyeW = normalize(p) * (dRadiusW + dAltitudeW)
    } else {
      dEyeW.x = x
      dEyeW.z = z
    }
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
