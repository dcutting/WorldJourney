import Metal

class Tessellator {
  let tessellationPipelineState: MTLComputePipelineState
  let controlPointsBuffer: MTLBuffer
  let tessellationFactorsBuffer: MTLBuffer
  let patchCount: Int
    
  init(device: MTLDevice, library: MTLLibrary, patchesPerSide: Int) {
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
    let controlPoints = createControlPoints(patches: patches, size: 2.0)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!, controlPoints.count/4)
  }
  
  private static func makeFactorsBuffer(device: MTLDevice, patchCount: Int) -> MTLBuffer {
    let count = patchCount * (4 + 2)  // 4 edges + 2 insides
    let size = count * MemoryLayout<Float>.size / 2 // "half floats"
    return device.makeBuffer(length: size, options: .storageModePrivate)!
  }

  func doTessellationPass(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms) {
    var uniforms = uniforms
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
    computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 3)
    computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
    computeEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 5)
    
//    let w = min(patches, tessellationPipelineState.threadExecutionWidth)
//    let h = min(patches, tessellationPipelineState.maxTotalThreadsPerThreadgroup / w)
//    let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
//    let threads = MTLSizeMake(patches, patches, 1)
//    computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
    
    let width = min(patchCount, tessellationPipelineState.threadExecutionWidth)
    computeEncoder.dispatchThreads(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
  }
}

func createControlPoints(patches: Int, size: Float) -> [SIMD3<Float>] {
  
  var points: [SIMD3<Float>] = []
  // per patch width and height
  let width = 1 / Float(patches)
  
//  let window = 10
//  let patches/2-window
//  let patches/2+window
  let start = 0
  let end = patches
  for j in start..<end {
    let row = Float(j)
    for i in start..<end {
      let column = Float(i)
      let left = width * column
      let bottom = width * row
      let right = width * column + width
      let top = width * row + width
      points.append([left, top, 0])
      points.append([right, top, 0])
      points.append([right, bottom, 0])
      points.append([left, bottom, 0])
    }
  }
  // size and convert to Metal coordinates
  // eg. 6 across would be -3 to + 3
  points = points.map {
    [$0.x * size - size / 2,
     $0.y * size - size / 2,
     0]
  }
  return points
}
