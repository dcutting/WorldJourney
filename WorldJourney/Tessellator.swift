import Metal

class Tessellator {
  let device: MTLDevice
  let library: MTLLibrary
  let tessellationPipelineState: MTLComputePipelineState
  var controlPointsBuffer: MTLBuffer
  let patches: Int
  let patchCount: Int
  
  lazy var tessellationFactorsBuffer: MTLBuffer? = {
    let count = patchCount * (4 + 2)  // 4 edges + 2 insides
    let size = count * MemoryLayout<Float>.size / 2 // "half floats"
    return device.makeBuffer(length: size, options: .storageModePrivate)
  }()
  
  init(device: MTLDevice, library: MTLLibrary, patchesPerSide: Int) {
    self.device = device
    self.library = library
    self.patches = patchesPerSide
    self.tessellationPipelineState = Self.makeTessellationPipelineState(device: device, library: library)
    (self.controlPointsBuffer, self.patchCount) = Self.makeControlPointsBuffer(patches: patches, device: device)
  }

  private static func makeTessellationPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "tessellation_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Tessellation kernel function not found.") }
    return state
  }
  
  private static func makeControlPointsBuffer(patches: Int, device: MTLDevice) -> (MTLBuffer, Int) {
    let controlPoints = createControlPoints(patches: patches, size: 2.0)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!, controlPoints.count/4)
  }
  
  func doTessellationPass(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms) {
    var uniforms = uniforms
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
//    let w = min(patches, tessellationPipelineState.threadExecutionWidth)
    let width = min(patchCount, tessellationPipelineState.threadExecutionWidth)
    computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 3)
    computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
    computeEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 5)
    
//    let h = min(patches, tessellationPipelineState.maxTotalThreadsPerThreadgroup / w)
//    let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
//    let threads = MTLSizeMake(patches, patches, 1)
//    computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
    computeEncoder.dispatchThreads(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
    computeEncoder.endEncoding()
  }
}
