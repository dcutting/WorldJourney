import MetalKit

class Renderer: NSObject, MTKViewDelegate {
  private let view: MTKView
  private let device = MTLCreateSystemDefaultDevice()!
  private lazy var commandQueue = device.makeCommandQueue()!
  private var pipelineState: MTLRenderPipelineState!
  private var depthStencilState: MTLDepthStencilState!
  private let fov: Float
  private var gridVertices = [simd_float2]()
  private var levelVertices = [simd_float2]()
  private let gridBuffer: MTLBuffer
  private let levelBuffer: MTLBuffer
  private var time: Float = 0

  init?(metalKitView: MTKView) {
    self.view = metalKitView
    metalKitView.depthStencilPixelFormat = .depth32Float
    fov = calculateFieldOfView(degrees: 48)
    let library = device.makeDefaultLibrary()!
    pipelineState = Self.makePipelineState(device: device, library: library, metalView: view)
    depthStencilState = Self.makeDepthStencilState(device: device)
    gridVertices = Self.createVertexPoints(patches: 650, size: 1)
    levelVertices = Self.createVertexPoints(patches: 8, size: 1)
    gridBuffer = device.makeBuffer(bytes: gridVertices, length: gridVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
    levelBuffer = device.makeBuffer(bytes: levelVertices, length: levelVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
  }
  
  func draw(in view: MTKView) {
    guard
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    let projectionMatrix = makeProjectionMatrix(w: view.bounds.width,
                                                h: view.bounds.height,
                                                fov: fov,
                                                farZ: 2000.0)
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
    time += 0.005
    let modelMatrix = matrix_float4x4(diagonal: simd_float4(repeating: 1))
    let distance: Float = sin(time*3)*0.5+1;
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time)*distance, 0.6, cos(time)*distance), up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(time*3-3, 0.7, 1), up: simd_float3(0, 1, 0))
    let viewMatrix = look(at: .zero, eye: simd_float3(0, 0.7, 1), up: simd_float3(0, 1, 0))
//    let viewMatrix = look(at: .zero, eye: simd_float3(sin(time*2)/2, 0.7, 1), up: simd_float3(0, 1, 0))
//    let eye = simd_float3(0, 0.5, 1);
//    let viewMatrix = matrix_float4x4(translationBy: -eye)
    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    encoder.setTriangleFillMode(.fill)
    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthStencilState)
    
    encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
    var uniforms = Uniforms(modelMatrix: modelMatrix,
                            viewMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            ambientColour: simd_float3(0.2, 0.2, 0.2),
                            drawLevel: 0,
                            level: 0.0,
                            time: time)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertices.count)
    
    let drawLevels = true
    if drawLevels {
      encoder.setVertexBuffer(levelBuffer, offset: 0, index: 0)
      encoder.setTriangleFillMode(.lines)
      var uniforms2 = Uniforms(modelMatrix: modelMatrix,
                               viewMatrix: viewMatrix,
                               projectionMatrix: projectionMatrix,
                               ambientColour: simd_float3(0, 0, 1),
                               drawLevel: 1,
                               level: -1.0,
                               time: time)
      encoder.setVertexBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFragmentBytes(&uniforms2, length: MemoryLayout<Uniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
      var uniforms3 = Uniforms(modelMatrix: modelMatrix,
                               viewMatrix: viewMatrix,
                               projectionMatrix: projectionMatrix,
                               ambientColour: simd_float3(0, 0, 1),
                               drawLevel: 1,
                               level: 0.0,
                               time: time)
      encoder.setVertexBytes(&uniforms3, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFragmentBytes(&uniforms3, length: MemoryLayout<Uniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
      var uniforms4 = Uniforms(modelMatrix: modelMatrix,
                               viewMatrix: viewMatrix,
                               projectionMatrix: projectionMatrix,
                               ambientColour: simd_float3(0, 0, 1),
                               drawLevel: 1,
                               level: 1.0,
                               time: time)
      encoder.setVertexBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.setFragmentBytes(&uniforms4, length: MemoryLayout<Uniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: levelVertices.count)
    }
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  private static func createVertexPoints(patches: Int, size: Float) -> [simd_float2] {
    var points: [simd_float2] = []
    let width: Float = size / Float(patches)

    for j in 0..<patches {
      let row: Float = Float(j)
      for i in 0..<patches {
        let column: Float = Float(i)
        let left: Float = width * column
        let bottom: Float = width * row
        let right: Float = width * column + width
        let top: Float = width * row + width
        points.append([left, top])
        points.append([right, top])
        points.append([left, bottom])
        points.append([right, top])
        points.append([right, bottom])
        points.append([left, bottom])
      }
    }
    // size and convert to Metal coordinates
    // eg. 6 across would be -3 to + 3
    let hSize: Float = size / 2.0
    points = points.map {
      [$0.x - hSize,
       ($0.y - hSize)]
    }
    return points
  }

  
  private static func makePipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.vertexFunction = library.makeFunction(name: "terrainium_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "terrainium_fragment")
    return try! device.makeRenderPipelineState(descriptor: descriptor)
  }
  
  private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: descriptor)!
  }
}
