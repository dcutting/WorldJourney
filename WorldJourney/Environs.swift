import Metal

class Environs {
  let heightPipelineState: MTLComputePipelineState

  init(device: MTLDevice, library: MTLLibrary) {
    heightPipelineState = Self.makeHeightPipelineState(device: device, library: library)
  }

  private static func makeHeightPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "height_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Height kernel function not found.") }
    return state
  }

  func computeHeight(heightEncoder: MTLComputeCommandEncoder, uniforms: Uniforms, position: vector_float3, groundLevelBuffer: MTLBuffer, normalBuffer: MTLBuffer) {
    var uniforms = uniforms
    var p = position
    heightEncoder.setComputePipelineState(heightPipelineState)
    heightEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    heightEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 1)
    heightEncoder.setBytes(&p, length: MemoryLayout<SIMD3<Float>>.stride, index: 2)
    heightEncoder.setBuffer(groundLevelBuffer, offset: 0, index: 3)
    heightEncoder.setBuffer(normalBuffer, offset: 0, index: 4)
    heightEncoder.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
    heightEncoder.endEncoding()
  }
}
