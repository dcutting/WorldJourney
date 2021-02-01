import Metal
import PhyKit

class Environs {
  let pipelineState: MTLComputePipelineState
  let controlPointsBuffer: MTLBuffer
  let meshBuffer: MTLBuffer
  let patchesPerSide: Int
  let patchCount: Int

  init(device: MTLDevice, library: MTLLibrary, patchesPerSide: Int) {
    self.patchesPerSide = patchesPerSide
    pipelineState = Self.makeHeightPipelineState(device: device, library: library)
    (self.controlPointsBuffer, self.patchCount) = Self.makeControlPointsBuffer(patches: patchesPerSide, device: device)
    self.meshBuffer = Self.makeBuffer(device: device, patchCount: patchCount)
  }

  private static func makeHeightPipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
    guard
      let function = library.makeFunction(name: "height_kernel"),
      let state = try? device.makeComputePipelineState(function: function)
      else { fatalError("Height kernel function not found.") }
    return state
  }

  private static func makeControlPointsBuffer(patches: Int, device: MTLDevice) -> (MTLBuffer, Int) {
    let controlPoints = createEnvironsControlPoints(patches: patches, size: 2.0)
    return (device.makeBuffer(bytes: controlPoints, length: MemoryLayout<SIMD3<Float>>.stride * controlPoints.count)!, controlPoints.count)
  }

  private static func makeBuffer(device: MTLDevice, patchCount: Int) -> MTLBuffer {
    let count = patchCount
    let size = count * MemoryLayout<simd_float3>.size
    return device.makeBuffer(length: size, options: .storageModeShared)!
  }

  func computeHeight(heightEncoder: MTLComputeCommandEncoder, position: vector_float3) {
    var p = position
    heightEncoder.setComputePipelineState(pipelineState)
    heightEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 0)
    heightEncoder.setBytes(&p, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
    heightEncoder.setBytes(&Renderer.terrain, length: MemoryLayout<Terrain>.stride, index: 2)
    heightEncoder.setBuffer(meshBuffer, offset: 0, index: 3)

    let width = min(patchCount, pipelineState.threadExecutionWidth)
    heightEncoder.dispatchThreads(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
  }
  
  func makeGroundMesh() -> [[PHYVector3]] {
    // TODO: environs mesh is probably much bigger than it needs to be
    var groundSamples = [simd_float3](repeating: .zero, count: patchCount)
    let groundSampleData = NSData(bytesNoCopy: meshBuffer.contents(),
                                  length: meshBuffer.length,
                                  freeWhenDone: false)
    groundSampleData.getBytes(&groundSamples, length: meshBuffer.length)
    var mesh = [[PHYVector3]]()
    let s = patchesPerSide
    for j in 0..<(s-1) {
      for i in 0..<(s-1) {
        mesh.append([
          groundSamples[j*s+i+1].phyVector3,
          groundSamples[j*s+i].phyVector3,
          groundSamples[(j+1)*s+i].phyVector3
        ])
        mesh.append([
          groundSamples[j*s+i+1].phyVector3,
          groundSamples[(j+1)*s+i].phyVector3,
          groundSamples[(j+1)*s+i+1].phyVector3
        ])
      }
    }
    return mesh
  }
}

func createEnvironsControlPoints(patches: Int, size: Float) -> [SIMD3<Float>] {
  
  var points: [SIMD3<Float>] = []
  // per patch width and height
  let width = 1 / Float(patches - 1)
  
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
      let top = width * row
      points.append([left, top, 0])
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
