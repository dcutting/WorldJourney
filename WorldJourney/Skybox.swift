import MetalKit

class Skybox {
  
  let device: MTLDevice
  let mesh: MTKMesh
  var texture: MTLTexture?
  let pipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState?
  
  init(device: MTLDevice, library: MTLLibrary, metalView: MTKView, textureName: String) {
    self.device = device
    let allocator = MTKMeshBufferAllocator(device: device)
    let cube = MDLMesh(boxWithExtent: [1,1,1], segments: [1, 1, 1],
                       inwardNormals: true, geometryType: .triangles,
                       allocator: allocator)
    do {
      mesh = try MTKMesh(mesh: cube, device: device)
    } catch {
      fatalError("failed to create skybox mesh")
    }
    pipelineState = Skybox.buildPipelineState(
      device: device,
      library: library,
      metalView: metalView,
      vertexDescriptor: cube.vertexDescriptor
    )
    depthStencilState = Skybox.buildDepthStencilState(device: device)
    do {
      texture = try Skybox.loadCubeTexture(device: device, imageName: textureName)
    } catch {
      fatalError(error.localizedDescription)
    }
  }
  
  private static func buildPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView, vertexDescriptor: MDLVertexDescriptor)
  -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.vertexFunction =
      library.makeFunction(name: "skybox_vertex")
    descriptor.fragmentFunction =
      library.makeFunction(name: "skybox_fragment")
    descriptor.vertexDescriptor =
      MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
    do {
      return
        try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
      fatalError(error.localizedDescription)
    }
  }
  
  private static func buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: descriptor)
  }
  
  private static func loadCubeTexture(device: MTLDevice, imageName: String) throws -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option: Any] = [
      .textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))
    ]
    let texture = try textureLoader.newTexture(
      name: imageName,
      scaleFactor: 1.0,
      bundle: .main,
      options: options
    )
    return texture
  }

  func update(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setFragmentTexture(texture, index: 0)
  }
  
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    renderEncoder.pushDebugGroup("Skybox")
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)
    var viewMatrix = uniforms.viewMatrix
    viewMatrix.columns.3 = [0, 0, 0, 1]
    var viewProjectionMatrix = uniforms.projectionMatrix * viewMatrix
    renderEncoder.setVertexBytes(&viewProjectionMatrix,
                                 length: MemoryLayout<float4x4>.stride,
                                 index: 1)
    let submesh = mesh.submeshes[0]
    var uniforms = uniforms
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    renderEncoder.setFragmentTexture(texture, index: Int(0))
    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                        indexCount: submesh.indexCount,
                                        indexType: submesh.indexType,
                                        indexBuffer: submesh.indexBuffer.buffer,
                                        indexBufferOffset: 0)
  }
}
