// https://github.com/metal-by-example/modelio-materials

import Foundation
import MetalKit
import simd

enum TextureIndex: Int {
  case baseColor = 4
  case metallic = 5
  case roughness = 6
  case normal = 7
  case emissive = 8
//  case irradiance = 9
}

enum VertexBufferIndex: Int {
  case attributes = 0
  case uniforms = 1
  case instanceUniforms = 2
}

enum FragmentBufferIndex: Int {
  case uniforms = 0
}

class Material {
  var baseColor: MTLTexture?
  var metallic: MTLTexture?
  var roughness: MTLTexture?
  var normal: MTLTexture?
  var emissive: MTLTexture?
  
  func texture(for semantic: MDLMaterialSemantic, in material: MDLMaterial?, textureLoader: MTKTextureLoader) -> MTLTexture? {
    guard let materialProperty = material?.property(with: semantic) else { return nil }
    guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
    // NOTE: work with some models, not others.
    let wantMips = false//materialProperty.semantic != .tangentSpaceNormal
    let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : wantMips ]
    return try? textureLoader.newTexture(texture: sourceTexture, options: options)
  }
  
  init(material sourceMaterial: MDLMaterial?, textureLoader: MTKTextureLoader) {
    baseColor = texture(for: .baseColor, in: sourceMaterial, textureLoader: textureLoader)
    metallic = texture(for: .metallic, in: sourceMaterial, textureLoader: textureLoader)
    roughness = texture(for: .roughness, in: sourceMaterial, textureLoader: textureLoader)
    normal = texture(for: .tangentSpaceNormal, in: sourceMaterial, textureLoader: textureLoader)
    emissive = texture(for: .emission, in: sourceMaterial, textureLoader: textureLoader)
  }
}

class Node {
  var modelMatrix: float4x4
  let mesh: MTKMesh
  let materials: [Material]
  
  init(mesh: MTKMesh, materials: [Material]) {
    assert(mesh.submeshes.count == materials.count)
    
    modelMatrix = matrix_identity_float4x4
    self.mesh = mesh
    self.materials = materials
  }
}

class Objects {
  let renderPipeline: MTLRenderPipelineState
  let vertexDescriptor: MDLVertexDescriptor
  var renderPassDescriptor: MTLRenderPassDescriptor!
  
  var albedoTexture: MTLTexture!
  var normalTexture: MTLTexture!
  var positionTexture: MTLTexture!
  var depthTexture: MTLTexture!

  let textureLoader: MTKTextureLoader
  let defaultTexture: MTLTexture
  let defaultNormalMap: MTLTexture
//  let irradianceCubeMap: MTLTexture
  
  var instanceUniformsBuffer: MTLBuffer!

  var nodes = [Node]()
  
  init(device: MTLDevice, library: MTLLibrary) {
    vertexDescriptor = Self.buildVertexDescriptor(device: device)
    renderPipeline = Self.buildPipeline(device: device, library: library, vertexDescriptor: vertexDescriptor)
    textureLoader = MTKTextureLoader(device: device)
    (defaultTexture, defaultNormalMap) = Self.buildDefaultTextures(device: device)
//    irradianceCubeMap = Self.buildEnvironmentTexture("space-sky", device: device)
    
    guard let modelURL = Bundle.main.url(forResource: "Moss_Rock_14_Free_Rock_Pack_Vol", withExtension: "usdz") else {
      fatalError("Could not find model file in app bundle")
    }
    buildScene(url: modelURL, device: device, vertexDescriptor: vertexDescriptor)
  }
  
  static func buildVertexDescriptor(device: MTLDevice) -> MDLVertexDescriptor {
    let vertexDescriptor = MDLVertexDescriptor()
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                        format: .float3,
                                                        offset: 0,
                                                        bufferIndex: VertexBufferIndex.attributes.rawValue)
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                        format: .float3,
                                                        offset: MemoryLayout<Float>.size * 3,
                                                        bufferIndex: VertexBufferIndex.attributes.rawValue)
    vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTangent,
                                                        format: .float3,
                                                        offset: MemoryLayout<Float>.size * 6,
                                                        bufferIndex: VertexBufferIndex.attributes.rawValue)
    vertexDescriptor.attributes[3] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                        format: .float3,
                                                        offset: MemoryLayout<Float>.size * 9,
                                                        bufferIndex: VertexBufferIndex.attributes.rawValue)
    vertexDescriptor.layouts[VertexBufferIndex.attributes.rawValue] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 12)
    return vertexDescriptor
  }
  
  static func buildPipeline(device: MTLDevice, library: MTLLibrary, vertexDescriptor: MDLVertexDescriptor) -> MTLRenderPipelineState {
    
    let vertexFunction = library.makeFunction(name: "objects_vertex")
    let fragmentFunction = library.makeFunction(name: "objects_fragment")
    
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDescriptor.colorAttachments[1].pixelFormat = .rgba16Float
    pipelineDescriptor.colorAttachments[2].pixelFormat = .rgba32Float
    pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
    pipelineDescriptor.label = "Object state"
    
    let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
    pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
    
    do {
      return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch {
      fatalError("Could not create render pipeline state object: \(error)")
    }
  }
  
  func buildRenderPassDescriptor() {
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
    self.renderPassDescriptor = objectRenderPassDescriptor
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
  
  static func buildEnvironmentTexture(_ name: String, device:MTLDevice) -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option : Any] = [:]
    do {
      let textureURL = Bundle.main.url(forResource: name, withExtension: nil)!
      let texture = try textureLoader.newTexture(URL: textureURL, options: options)
      return texture
    } catch {
      fatalError("Could not load irradiance map from asset catalog: \(error)")
    }
  }
  
  func buildScene(url: URL, device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) {
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: bufferAllocator)
    
    asset.loadTextures()
    
    for sourceMesh in asset.childObjects(of: MDLMesh.self) as! [MDLMesh] {
      sourceMesh.addOrthTanBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                 normalAttributeNamed: MDLVertexAttributeNormal,
                                 tangentAttributeNamed: MDLVertexAttributeTangent)
      // NOTE: some models need texture coordinates flipped, some don't. How do we know?
      sourceMesh.flipTextureCoordinates(inAttributeNamed: MDLVertexAttributeTextureCoordinate)
      sourceMesh.vertexDescriptor = vertexDescriptor
    }
    
    guard let (sourceMeshes, meshes) = try? MTKMesh.newMeshes(asset: asset, device: device) else {
      fatalError("Could not convert ModelIO meshes to MetalKit meshes")
    }
    
    for (sourceMesh, mesh) in zip(sourceMeshes, meshes) {
      var materials = [Material]()
      for sourceSubmesh in sourceMesh.submeshes as! [MDLSubmesh] {
        let material = Material(material: sourceSubmesh.material, textureLoader: textureLoader)
        materials.append(material)
      }
      let node = Node(mesh: mesh, materials: materials)
      nodes.append(node)
    }
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
  }
  
  func bindTextures(_ material: Material, _ commandEncoder: MTLRenderCommandEncoder) {
    commandEncoder.setFragmentTexture(material.baseColor ?? defaultTexture, index: TextureIndex.baseColor.rawValue)
    commandEncoder.setFragmentTexture(material.metallic ?? defaultTexture, index: TextureIndex.metallic.rawValue)
    commandEncoder.setFragmentTexture(material.roughness ?? defaultTexture, index: TextureIndex.roughness.rawValue)
    commandEncoder.setFragmentTexture(material.normal ?? defaultNormalMap, index: TextureIndex.normal.rawValue)
    commandEncoder.setFragmentTexture(material.emissive ?? defaultTexture, index: TextureIndex.emissive.rawValue)
  }
  
  func render(commandBuffer: MTLCommandBuffer, uniforms: Uniforms, depthStencilState: MTLDepthStencilState) {
    let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    commandEncoder.setRenderPipelineState(renderPipeline)
    commandEncoder.setDepthStencilState(depthStencilState)
//    commandEncoder.setFragmentTexture(irradianceCubeMap, index: TextureIndex.irradiance.rawValue)
    for node in nodes {
      draw(node, in: commandEncoder, uniforms: uniforms)
    }
    commandEncoder.endEncoding()
  }
  
  func makeInstanceUniforms(device: MTLDevice) {
    let numInstances = 10
    let instanceUniforms = (0..<numInstances).map { i -> InstanceUniforms in
      let modelMatrix = matrix_float4x4(translationBy: SIMD3<Float>(x: Float(i-(numInstances/2)) * 500, y: 5150, z: 0)) * matrix_float4x4(scaleBy: 10)
      let modelNormalMatrix = modelMatrix.normalMatrix
      return InstanceUniforms(modelMatrix: modelMatrix, modelNormalMatrix: modelNormalMatrix)
    }
    let size = MemoryLayout<InstanceUniforms>.size * numInstances
    instanceUniformsBuffer = device.makeBuffer(bytes: instanceUniforms, length: size, options: .storageModeShared)!
  }
  
  func draw(_ node: Node, in commandEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    let mesh = node.mesh
    
    var uniforms = uniforms
    let modelMatrix = matrix_float4x4(translationBy: SIMD3<Float>(x: 0, y: 5150, z: 0)) * matrix_float4x4(scaleBy: 10)
    let modelNormalMatrix = modelMatrix.normalMatrix

    var instanceUniforms = InstanceUniforms(modelMatrix: modelMatrix, modelNormalMatrix: modelNormalMatrix)
    
    commandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: VertexBufferIndex.uniforms.rawValue)
    commandEncoder.setVertexBytes(&instanceUniforms, length: MemoryLayout<InstanceUniforms>.size, index: VertexBufferIndex.instanceUniforms.rawValue)
    commandEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: FragmentBufferIndex.uniforms.rawValue)
    
    for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
      commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: bufferIndex)
    }
    
    for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
      let material = node.materials[submeshIndex]
      bindTextures(material, commandEncoder)
      
      let indexBuffer = submesh.indexBuffer
      commandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                           indexCount: submesh.indexCount,
                                           indexType: submesh.indexType,
                                           indexBuffer: indexBuffer.buffer,
                                           indexBufferOffset: indexBuffer.offset)
//              instanceCount: numInstances)
    }
  }
}
