import MetalKit

class Tessellator {
  let device: MTLDevice
  let tessellationPipelineState: MTLComputePipelineState
//  let controlPointsBuffer: MTLBuffer
//  let tessellationFactorsBuffer: MTLBuffer
//  let patchCount: Int
//  let patchesPerSide: Int

  init(device: MTLDevice, library: MTLLibrary) {//}, patchesPerSide: Int) {
    self.device = device
//    self.patchesPerSide = patchesPerSide
    self.tessellationPipelineState = Self.makeTessellationPipelineState(device: device, library: library)
//    self.patchCount = patchCount
//    (self.controlPointsBuffer, self.patchCount) = Self.makeControlPointsBuffer(patches: patchesPerSide, device: device)
//    self.tessellationFactorsBuffer = Self.makeFactorsBuffer(device: device, patchCount: patchCount)
  }
  
  private static func makeTessellationPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "tessellation_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Tessellation kernel function not found.") }
    return state
  }
  
//  private static func makeControlPointsBuffer(patches: Int, device: MTLDevice) -> (MTLBuffer, Int) {
//    let controlPoints = createControlPoints(patches: patches, size: 4)
//    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!,
//            controlPoints.count / 4)
//  }

  static func makeFactorsBuffer(device: MTLDevice, patchCount: Int) -> MTLBuffer {
    let count = patchCount * (4 + 2)  // 4 edges + 2 insides
    let size = count * MemoryLayout<Float>.size
    return device.makeBuffer(length: size, options: .storageModePrivate)!
  }

//  func getBuffers(uniforms: Uniforms) -> (MTLBuffer, MTLBuffer, Int, Int) {
//    (tessellationFactorsBuffer, controlPointsBuffer, patchesPerSide, patchCount)
//  }

  func doTessellationPass(
    computeEncoder: MTLComputeCommandEncoder,
    uniforms: Uniforms,
//    factors: MTLBuffer,
    points: MTLBuffer,
    quadUniforms: MTLBuffer,
    patchCount: Int
  ) -> MTLBuffer {
//    let (factors, points, _, count) = getBuffers(uniforms: uniforms)
    let factors = Self.makeFactorsBuffer(device: device, patchCount: patchCount)
    var uniforms = uniforms
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setBuffer(factors, offset: 0, index: 2)
    computeEncoder.setBuffer(points, offset: 0, index: 3)
    computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
    computeEncoder.setBuffer(quadUniforms, offset: 0, index: 5)
    let width = min(patchCount, tessellationPipelineState.threadExecutionWidth)
    computeEncoder.dispatchThreads(
      MTLSizeMake(patchCount, 1, 1),
      threadsPerThreadgroup: MTLSizeMake(width, 1, 1)
    )
    return factors
  }
}

//func createControlPoints(patches: Int, size: Float) -> [SIMD3<Float>] {
//  var points: [SIMD3<Float>] = []
//  let patchWidth = 1 / Float(patches)
//  let start = 0
//  let end = patches
//  for j in start..<end {
//    let row = Float(j)
//    for i in start..<end {
//      let column = Float(i)
//      let left = patchWidth * column
//      let bottom = patchWidth * row
//      let right = patchWidth * column + patchWidth
//      let top = patchWidth * row + patchWidth
//      points.append([left, top, 0])
//      points.append([right, top, 0])
//      points.append([right, bottom, 0])
//      points.append([left, bottom, 0])
//    }
//  }
//  // Size and convert to Metal coordinates. E.g., 6 across would be -3 to + 3.
//  points = points.map {[
//    $0.x * size - size / 2,
//    $0.y * size - size / 2,
//    0
//  ]}
//  return points
//}
