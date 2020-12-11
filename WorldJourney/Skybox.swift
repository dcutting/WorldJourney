import MetalKit

class Skybox {
  
  let device: MTLDevice
  let mesh: MTKMesh
  var texture: MTLTexture?
  let pipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState?
  
  struct SkySettings {
    var turbidity: Float = 0.28
    var sunElevation: Float = 0.6
    var upperAtmosphereScattering: Float = 0.1
    var groundAlbedo: Float = 4
  }
  
  var skySettings = SkySettings()
  
  init(device: MTLDevice, library: MTLLibrary, metalView: MTKView, textureName: String?) {
    self.device = device
    let allocator = MTKMeshBufferAllocator(device: device)
    let cube = MDLMesh(boxWithExtent: [1,1,1], segments: [1, 1, 1],
                       inwardNormals: true, geometryType: .triangles,
                       allocator: allocator)
    do {
      mesh = try MTKMesh(mesh: cube,
                         device: device)
    } catch {
      fatalError("failed to create skybox mesh")
    }
    pipelineState =
      Skybox.buildPipelineState(device: device, library: library, metalView: metalView, vertexDescriptor: cube.vertexDescriptor)
    depthStencilState = Skybox.buildDepthStencilState(device: device)
    if let textureName = textureName {
      do {
        texture = try Skybox.loadCubeTexture(device: device, imageName: textureName)
      } catch {
        fatalError(error.localizedDescription)
      }
    } else {
      texture = loadGeneratedSkyboxTexture(dimensions: [256, 256])
    }
  }
  
  func loadGeneratedSkyboxTexture(dimensions: SIMD2<Int32>) -> MTLTexture? {
    var texture: MTLTexture?
    let skyTexture = MDLSkyCubeTexture(name: "sky",
                                       channelEncoding: .uInt8,
                                       textureDimensions: dimensions,
                                       turbidity: skySettings.turbidity,
                                       sunElevation: skySettings.sunElevation,
                                       upperAtmosphereScattering: skySettings.upperAtmosphereScattering,
                                       groundAlbedo: skySettings.groundAlbedo)
    do {
      let textureLoader = MTKTextureLoader(device: device)
      texture = try textureLoader.newTexture(texture: skyTexture,
                                             options: nil)
    } catch {
      print(error.localizedDescription)
    }
    return texture
  }
  
  private static func
  buildPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView, vertexDescriptor: MDLVertexDescriptor)
    -> MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
      descriptor.depthAttachmentPixelFormat = .depth32Float
      descriptor.vertexFunction =
        library.makeFunction(name: "vertexSkybox")
      descriptor.fragmentFunction =
        library.makeFunction(name: "fragmentSkybox")
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
  
  func update(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setFragmentTexture(texture,
                                     index: Int(0))
  }

  func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    renderEncoder.pushDebugGroup("Skybox")
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer,
                                  offset: 0, index: 0)
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
    renderEncoder.setFragmentTexture(texture,
                                     index: Int(0))
    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                        indexCount: submesh.indexCount,
                                        indexType: submesh.indexType,
                                        indexBuffer: submesh.indexBuffer.buffer,
                                        indexBufferOffset: 0)
  }
}

extension Skybox: Texturable {}

protocol Texturable {}

extension Texturable {
  static func loadTexture(device: MTLDevice, imageName: String) throws -> MTLTexture? {
    let textureLoader = MTKTextureLoader(device: device)
    
    let textureLoaderOptions: [MTKTextureLoader.Option: Any] =
      [.origin: MTKTextureLoader.Origin.bottomLeft,
       .SRGB: false,
       .generateMipmaps: NSNumber(booleanLiteral: true)]
    let fileExtension =
      URL(fileURLWithPath: imageName).pathExtension.isEmpty ?
        "png" : nil
    guard let url = Bundle.main.url(forResource: imageName,
                                    withExtension: fileExtension)
      else {
        let texture = try? textureLoader.newTexture(name: imageName,
                                        scaleFactor: 1.0,
                                        bundle: Bundle.main, options: nil)
        if texture != nil {
          print("loaded: \(imageName) from asset catalog")
        } else {
          print("Texture not found: \(imageName)")
        }
        return texture
    }
    
    let texture = try textureLoader.newTexture(URL: url,
                                               options: textureLoaderOptions)
    print("loaded texture: \(url.lastPathComponent)")
    return texture
  }
  
  static func loadTexture(device: MTLDevice, texture: MDLTexture) throws -> MTLTexture? {
    let textureLoader = MTKTextureLoader(device: device)
    let textureLoaderOptions: [MTKTextureLoader.Option: Any] =
      [.origin: MTKTextureLoader.Origin.bottomLeft,
       .SRGB: false,
       .generateMipmaps: NSNumber(booleanLiteral: true)]
    
    let texture = try? textureLoader.newTexture(texture: texture,
                                                options: textureLoaderOptions)
    print("loaded texture from MDLTexture")
    return texture
  }
  
  static func loadCubeTexture(device: MTLDevice, imageName: String) throws -> MTLTexture {
    let textureLoader = MTKTextureLoader(device: device)
    if let texture = MDLTexture(cubeWithImagesNamed: [imageName]) {
      let options: [MTKTextureLoader.Option: Any] =
        [.origin: MTKTextureLoader.Origin.topLeft,
         .SRGB: false,
         .generateMipmaps: NSNumber(booleanLiteral: false)]
      return try textureLoader.newTexture(texture: texture, options: options)
    }
    let texture = try textureLoader.newTexture(name: imageName, scaleFactor: 1.0,
                                               bundle: .main)
    return texture
  }

}
