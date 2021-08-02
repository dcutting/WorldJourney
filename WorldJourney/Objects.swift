import Metal
import MetalKit

class Objects {
  var objectPipelineState: MTLRenderPipelineState!
  var vertexDescriptor: MDLVertexDescriptor!
  var objectRenderPassDescriptor: MTLRenderPassDescriptor!
  var sourceMeshes: [MDLMesh] = []
  var objectMeshes: [MTKMesh] = []
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!
  var instanceUniformsBuffer: MTLBuffer!
  var numInstances = 10
  var nodes = [Node]()
  let defaultTexture: MTLTexture
  let defaultNormalMap: MTLTexture

  init(device: MTLDevice, library: MTLLibrary) {
    (defaultTexture, defaultNormalMap) = Self.buildDefaultTextures(device: device)

    (vertexDescriptor, objectPipelineState) = makeObjectDescriptors(device: device, library: library)
    loadObjects(device: device, library: library)
    makeInstanceUniforms(device: device)
  }

  static func buildDefaultTextures(device: MTLDevice) -> (MTLTexture, MTLTexture) {
      let bounds = MTLRegionMake2D(0, 0, 1, 1)
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                width: bounds.size.width,
                                                                height: bounds.size.height,
                                                                mipmapped: false)
      descriptor.usage = .shaderRead
      let defaultTexture = device.makeTexture(descriptor: descriptor)!
      let defaultColor: [UInt8] = [ 0, 0, 0, 255 ]
      defaultTexture.replace(region: bounds, mipmapLevel: 0, withBytes: defaultColor, bytesPerRow: 4)
      let defaultNormalMap = device.makeTexture(descriptor: descriptor)!
      let defaultNormal: [UInt8] = [ 127, 127, 255, 255 ]
      defaultNormalMap.replace(region: bounds, mipmapLevel: 0, withBytes: defaultNormal, bytesPerRow: 4)
      return (defaultTexture, defaultNormalMap)
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
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                        format: .float3,
                                                        offset: 0,
                                                        bufferIndex: 0)
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                        format: .float3,
                                                        offset: MemoryLayout<Float>.size * 3,
                                                        bufferIndex: 0)
    vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTangent,
                                                        format: .float3,
                                                        offset: MemoryLayout<Float>.size * 6,
                                                        bufferIndex: 0)
    vertexDescriptor.attributes[3] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                        format: .float2,
                                                        offset: MemoryLayout<Float>.size * 9,
                                                        bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 11)
    
    descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

    let state = try! device.makeRenderPipelineState(descriptor: descriptor)
    
    return (vertexDescriptor, state)
  }
  
  private func loadObjects(device: MTLDevice, library: MTLLibrary) {
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let modelURL = Bundle.main.url(forResource: "Moss_Rock_14_Free_Rock_Pack_Vol", withExtension: "usdz")!
    let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
    asset.loadTextures()

    for sourceMesh in asset.childObjects(of: MDLMesh.self) as! [MDLMesh] {
        sourceMesh.addOrthTanBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                   normalAttributeNamed: MDLVertexAttributeNormal,
                                   tangentAttributeNamed: MDLVertexAttributeTangent)
        sourceMesh.vertexDescriptor = vertexDescriptor
    }
    
    do {
        (sourceMeshes, objectMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
    } catch {
        fatalError("Could not extract meshes from Model I/O asset")
    }
    
    let textureLoader = MTKTextureLoader(device: device)
    for (sourceMesh, mesh) in zip(sourceMeshes, objectMeshes) {
        var materials = [Material]()
        for sourceSubmesh in sourceMesh.submeshes as! [MDLSubmesh] {
            let material = Material(material: sourceSubmesh.material, textureLoader: textureLoader)
            materials.append(material)
        }
        let node = Node(mesh: mesh, materials: materials)
        nodes.append(node)
    }
  }
  
  func makeInstanceUniforms(device: MTLDevice) {
    let instanceUniforms = (0..<numInstances).map { i -> InstanceUniforms in
      let modelMatrix = matrix_float4x4(translationBy: SIMD3<Float>(x: Float(i-(numInstances/2)) * 500, y: 5150, z: 0)) * matrix_float4x4(scaleBy: 10)
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
  
  enum TextureIndex: Int {
      case baseColor
      case metallic
      case roughness
      case normal
      case emissive
      case irradiance = 9
  }

  func renderObjects(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, compositor: Compositor) {
    renderEncoder.setRenderPipelineState(objectPipelineState)
    renderEncoder.setDepthStencilState(compositor.depthStencilState)
    var uniforms = uniforms
    for node in nodes {
      
      let mesh = node.mesh
      
      renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      renderEncoder.setVertexBuffer(instanceUniformsBuffer, offset: 0, index: 2)
      renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)


      for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
        renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: bufferIndex)
      }

      for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
        let material = node.materials[submeshIndex]

      renderEncoder.setFragmentTexture(material.baseColor ?? defaultTexture, index: TextureIndex.baseColor.rawValue)
      renderEncoder.setFragmentTexture(material.metallic ?? defaultTexture, index: TextureIndex.metallic.rawValue)
      renderEncoder.setFragmentTexture(material.roughness ?? defaultTexture, index: TextureIndex.roughness.rawValue)
      renderEncoder.setFragmentTexture(material.normal ?? defaultNormalMap, index: TextureIndex.normal.rawValue)
      renderEncoder.setFragmentTexture(material.emissive ?? defaultTexture, index: TextureIndex.emissive.rawValue)

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

class Node {
    var modelMatrix: float4x4
    let mesh: MTKMesh
    let materials: [Material]
 
    init(mesh: MTKMesh, materials: [Material]) {
        modelMatrix = matrix_identity_float4x4
        self.mesh = mesh
        self.materials = materials
    }
}

class Material {
  var baseColor: MTLTexture?
  var metallic: MTLTexture?
  var roughness: MTLTexture?
  var normal: MTLTexture?
  var emissive: MTLTexture?
  
  init(material sourceMaterial: MDLMaterial?, textureLoader: MTKTextureLoader) {
    baseColor = texture(for: .baseColor, in: sourceMaterial, textureLoader: textureLoader)
    metallic = texture(for: .metallic, in: sourceMaterial, textureLoader: textureLoader)
    roughness = texture(for: .roughness, in: sourceMaterial, textureLoader: textureLoader)
    normal = texture(for: .tangentSpaceNormal, in: sourceMaterial, textureLoader: textureLoader)
    emissive = texture(for: .emission, in: sourceMaterial, textureLoader: textureLoader)
  }

  func texture(for semantic: MDLMaterialSemantic, in material: MDLMaterial?, textureLoader: MTKTextureLoader) -> MTLTexture? {
    guard let materialProperty = material?.property(with: semantic) else { return nil }
    guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
    let wantMips = false//materialProperty.semantic != .tangentSpaceNormal
    let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : wantMips ]
    return try? textureLoader.newTexture(texture: sourceTexture, options: options)
  }
}
