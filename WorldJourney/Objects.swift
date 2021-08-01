import Metal
import MetalKit

class Objects {
  var objectPipelineState: MTLRenderPipelineState!
  var vertexDescriptor: MDLVertexDescriptor!
  var objectRenderPassDescriptor: MTLRenderPassDescriptor!
  var objectMeshes: [MTKMesh] = []
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!
  var instanceUniformsBuffer: MTLBuffer!
  var numInstances = 10

  init(device: MTLDevice, library: MTLLibrary) {
    (vertexDescriptor, objectPipelineState) = makeObjectDescriptors(device: device, library: library)
    loadObjects(device: device, library: library)
    makeInstanceUniforms(device: device)
  }

  private func makeObjectDescriptors(device: MTLDevice, library: MTLLibrary) -> (MDLVertexDescriptor, MTLRenderPipelineState) {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[1].pixelFormat = .rgba16Float
    descriptor.colorAttachments[2].pixelFormat = .rgba32Float
    descriptor.depthAttachmentPixelFormat = .depth32Float
    descriptor.label = "Object state"
    
    descriptor.vertexFunction = library.makeFunction(name: "object_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "object_fragment")
    
    let vertexDescriptor = MDLVertexDescriptor()
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
    vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<simd_float3>.size + MemoryLayout<simd_float3>.size + MemoryLayout<simd_float2>.size)

    descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

    let state = try! device.makeRenderPipelineState(descriptor: descriptor)
    
    return (vertexDescriptor, state)
  }
  
  private func loadObjects(device: MTLDevice, library: MTLLibrary) {
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let modelURL = Bundle.main.url(forResource: "toy_biplane", withExtension: "usdz")!
    let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
    
    do {
        (_, objectMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
    } catch {
        fatalError("Could not extract meshes from Model I/O asset")
    }
  }
  
  func makeInstanceUniforms(device: MTLDevice) {
    let instanceUniforms = (0..<numInstances).map { i -> InstanceUniforms in
      let modelMatrix = matrix_float4x4(translationBy: SIMD3<Float>(x: Float(i-(numInstances/2)) * 500, y: 5500, z: 0)) * matrix_float4x4(scaleBy: 10)
      let modelNormalMatrix = modelMatrix.inverse.transpose
      return InstanceUniforms(modelMatrix: modelMatrix, modelNormalMatrix: modelNormalMatrix)
    }
    let size = MemoryLayout<InstanceUniforms>.size * numInstances
    instanceUniformsBuffer = device.makeBuffer(bytes: instanceUniforms, length: size, options: .storageModeShared)!
  }

  func makeRenderPassDescriptors(device: MTLDevice, size: CGSize) {
    makeObjectRenderPassDescriptor(device: device, size: size)
  }

  func makeObjectRenderPassDescriptor(device: MTLDevice, size: CGSize) {
    let objectRenderPassDescriptor = MTLRenderPassDescriptor()
    
    // TODO: according to WWDC Metal lab engineers,
    // dontCare is probably what we want but that breaks the skybox currently.
    // Not sure how it could work.
    objectRenderPassDescriptor.setUpColorAttachment(position: 0,
                                                     texture: albedoTexture,
                                                     loadAction: .load)
    
    objectRenderPassDescriptor.setUpColorAttachment(position: 1,
                                                     texture: normalTexture,
                                                     loadAction: .load)
    objectRenderPassDescriptor.setUpColorAttachment(position: 2,
                                                     texture: positionTexture,
                                                     loadAction: .load)
    objectRenderPassDescriptor.setUpDepthAttachment(texture: depthTexture,
                                                     loadAction: .load,
                                                     storeAction: .store)
    self.objectRenderPassDescriptor = objectRenderPassDescriptor
  }
  
  func renderObjects(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, compositor: Compositor) {
    renderEncoder.setRenderPipelineState(objectPipelineState)
    renderEncoder.setDepthStencilState(compositor.depthStencilState)
    var uniforms = uniforms
    for mesh in objectMeshes {

      let vertexBuffer = mesh.vertexBuffers.first!
      renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
      renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      renderEncoder.setVertexBuffer(instanceUniformsBuffer, offset: 0, index: 2)
      renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
      
      for submesh in mesh.submeshes {
        let indexBuffer = submesh.indexBuffer
        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: indexBuffer.buffer,
                                            indexBufferOffset: indexBuffer.offset,
                                            instanceCount: numInstances)
      }
    }
  }
}
