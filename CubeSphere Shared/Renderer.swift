import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private var time: Float = 0
  private var eye: simd_float3 = simd_float3(0, 0, 0)
  
  init?(metalKitView: MTKView) {
    do {
      self.device = metalKitView.device!
      guard let queue = self.device.makeCommandQueue() else { return nil }
      self.commandQueue = queue
      metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
      metalKitView.colorPixelFormat = .bgra8Unorm_srgb
      metalKitView.sampleCount = 1
      
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
      return nil
    }
    super.init()
  }
  
  func draw(in view: MTKView) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
    if let renderPassDescriptor = view.currentRenderPassDescriptor,
       let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
      renderEncoder.setRenderPipelineState(pipelineState)
      renderEncoder.setDepthStencilState(depthState)
      time += 0.001
      eye.x = sin(time * 0.21) * 100.4
      eye.y = (cos(time * 0.38) + 1) * 10 + 4.2
      eye.z = -time * 10
      var uniforms = Uniforms(
        screenWidth: Float(view.drawableSize.width),
        screenHeight: Float(view.drawableSize.height),
        projectionMatrix: float4x4(),
        modelViewMatrix: float4x4(),
        time: time,
        eye: eye
      )
      renderEncoder.setObjectBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      let cells = 4
      let numRings = 3
      let oGroups = MTLSize(width: cells, height: cells, depth: numRings) // How many objects to make. No real limit.
      let oThreadsPerGroup = MTLSize(width: 1, height: 1, depth: 1)       // How to divide up the objects into work units.
      let mThreadsPerMesh = MTLSize(width: 1, height: 1, depth: 1)        // How many threads to work on each mesh.
      renderEncoder.drawMeshThreadgroups(oGroups,
                                         threadsPerObjectThreadgroup: oThreadsPerGroup,
                                         threadsPerMeshThreadgroup: mThreadsPerMesh)
      renderEncoder.endEncoding()
      if let drawable = view.currentDrawable {
        commandBuffer.present(drawable)
      }
    }
    commandBuffer.commit()
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
  }
}
