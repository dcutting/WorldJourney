import GameplayKit

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
  case terrain = 3
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
  let mesh: MTKMesh
  let materials: [Material]
  
  init(mesh: MTKMesh, materials: [Material]) {
    assert(mesh.submeshes.count == materials.count)
    self.mesh = mesh
    self.materials = materials
  }
}

struct SurfaceObjectConfiguration {
  let modelURL: URL
  let numInstances: Int
  let instanceRange: Float
  let viewDistance: Float
  let scale: ClosedRange<Double>
  let correction: matrix_float4x4
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
  
  let config: SurfaceObjectConfiguration
  
  var lastPosition = SIMD3<Float>(0, 0, 0)
  var instanceUniformsBuffer: MTLBuffer!
  var totalObjects = 0

  var nodes = [Node]()
  
  init(device: MTLDevice, library: MTLLibrary, config: SurfaceObjectConfiguration) {
    vertexDescriptor = Self.buildVertexDescriptor(device: device)
    renderPipeline = Self.buildPipeline(device: device, library: library, vertexDescriptor: vertexDescriptor)
    textureLoader = MTKTextureLoader(device: device)
    (defaultTexture, defaultNormalMap) = Self.buildDefaultTextures(device: device)
//    irradianceCubeMap = Self.buildEnvironmentTexture("space-sky", device: device)
    self.config = config
    buildScene(url: config.modelURL, device: device, vertexDescriptor: vertexDescriptor)
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
  
  func bindTextures(_ material: Material, _ commandEncoder: MTLRenderCommandEncoder) {
    commandEncoder.setFragmentTexture(material.baseColor ?? defaultTexture, index: TextureIndex.baseColor.rawValue)
    commandEncoder.setFragmentTexture(material.metallic ?? defaultTexture, index: TextureIndex.metallic.rawValue)
    commandEncoder.setFragmentTexture(material.roughness ?? defaultTexture, index: TextureIndex.roughness.rawValue)
    commandEncoder.setFragmentTexture(material.normal ?? defaultNormalMap, index: TextureIndex.normal.rawValue)
    commandEncoder.setFragmentTexture(material.emissive ?? defaultTexture, index: TextureIndex.emissive.rawValue)
  }
  
  func render(device: MTLDevice, commandBuffer: MTLCommandBuffer, uniforms: Uniforms, terrain: Terrain, depthStencilState: MTLDepthStencilState, wireframe: Bool) {
    let newNormalisedPosition = normalize(uniforms.cameraPosition) * terrain.sphereRadius
    if length(lastPosition) < 1 || distance(newNormalisedPosition, lastPosition) > config.instanceRange {
      makeInstanceUniforms(device: device, position: uniforms.cameraPosition, radius: terrain.sphereRadius)
      lastPosition = newNormalisedPosition
    }
    let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    commandEncoder.setTriangleFillMode(wireframe ? .lines : .fill)
    commandEncoder.setRenderPipelineState(renderPipeline)
    commandEncoder.setDepthStencilState(depthStencilState)
//    commandEncoder.setFragmentTexture(irradianceCubeMap, index: TextureIndex.irradiance.rawValue)
    for node in nodes {
      draw(node, in: commandEncoder, uniforms: uniforms, terrain: Renderer.terrain)
    }
    commandEncoder.endEncoding()
  }
  
  var objectCache = [UInt64: [InstanceUniforms]]()
  
  func makeInstanceUniforms(device: MTLDevice, position: SIMD3<Float>, radius: Float) {
    let q = normalize(position) * radius
    let cellSize = config.instanceRange
    let qh = spatialHash(position: q, cellSize: cellSize)
    let neighbours = findNeighbours(cell: qh, cellSize: cellSize, view: config.viewDistance, radius: radius)
    // TODO: optimisation is to only regenerate neighbours that are now different.
    let objects = neighbours.map { neighbour -> [InstanceUniforms] in
      let seed = seedHash(neighbour)
      if let scattered = objectCache[seed] {
        return scattered
      }
      let prng = ArbitraryRandomNumberGenerator(seed: seed)
      let center = findCenter(cell: neighbour, cellSize: cellSize)
      // TODO: number of objects scattered should be proportional to volume of cell inside sphere
      let scattered = scatterObjects(position: center, cellSize: cellSize, n: config.numInstances, prng: prng)
      objectCache[seed] = scattered
      return scattered
    }
    let instanceUniforms = Array(objects.joined())
    self.totalObjects = instanceUniforms.count
    let size = MemoryLayout<InstanceUniforms>.size * instanceUniforms.count
    instanceUniformsBuffer = device.makeBuffer(bytes: instanceUniforms, length: size, options: .storageModeShared)!
  }
  
  func spatialHash(position: SIMD3<Float>, cellSize: Float) -> SIMD3<Int> {
    SIMD3<Int>((position / cellSize).rounded(.down))
  }
  
  var neighbourCache = [SIMD3<Int>: [SIMD3<Int>]]()
  
  func findNeighbours(cell: SIMD3<Int>, cellSize: Float, view: Float, radius: Float) -> [SIMD3<Int>] {
    if let neighbours = neighbourCache[cell] {
      return neighbours
    }
    var neighbours = [SIMD3<Int>]()
    let r = Int(ceil(view/cellSize))
    for x in (-r...r) {
      for y in (-r...r) {
        for z in (-r...r) {
          let p = cell &+ SIMD3<Int>(x, y, z)
          if intersectsSurface(cell: p, cellSize: cellSize, radius: radius) {
            neighbours.append(p)
          }
        }
      }
    }
    neighbourCache[cell] = neighbours
    return neighbours
  }
  
  var intersectionCache = [SIMD3<Int>: Bool]()
  
  func intersectsSurface(cell: SIMD3<Int>, cellSize: Float, radius: Float) -> Bool {
    if let intersects = intersectionCache[cell] {
      return intersects
    }
    var corners = [SIMD3<Int>]()
    for x in (0...1) {
      for y in (0...1) {
        for z in (0...1) {
          let p = cell &+ SIMD3<Int>(x, y, z)
          corners.append(p)
        }
      }
    }
    let offsets = corners.map { c in
      length(SIMD3<Float>(c) * cellSize) - radius
    }
    let onOneSide = offsets.allSatisfy { x in
      x >= 0
    } || offsets.allSatisfy { x in
      x < 0
    }
    let intersects = !onOneSide
    intersectionCache[cell] = intersects
    return intersects
  }
  
  func seedHash(_ cell: SIMD3<Int>) -> UInt64 {
    var hasher = Hasher()
    hasher.combine(cell.x)
    hasher.combine(cell.y)
    hasher.combine(cell.z)
    return UInt64(abs(Int64(hasher.finalize())))
  }
  
  func findCenter(cell: SIMD3<Int>, cellSize: Float) -> SIMD3<Float> {
    (SIMD3<Float>(cell) + SIMD3<Float>(repeating: 0.5)) * cellSize
  }
  
  func scatterObjects(position: SIMD3<Float>, cellSize: Float, n: Int, prng: ArbitraryRandomNumberGenerator) -> [InstanceUniforms] {
    var prng = prng
    let halfCell = cellSize / 2
    return (0..<n).map { i -> InstanceUniforms in
      let coordinate = position + SIMD3<Float>(
        Float.random(in: -halfCell...halfCell, using: &prng),
        Float.random(in: -halfCell...halfCell, using: &prng),
        Float.random(in: -halfCell...halfCell, using: &prng)
      )
      // https://stackoverflow.com/questions/43101655/aligning-an-object-to-the-surface-of-a-sphere-while-maintaining-forward-directio
      let axis = simd_normalize(SIMD3<Float>(0, 1, 0))
      let surface = simd_normalize(coordinate)
      let east = simd_normalize(simd_cross(axis, surface))
      let north = simd_normalize(simd_cross(surface, east))
      let baseRotation = matrix_float4x4(
        SIMD4<Float>(east.x, east.y, east.z, 0),
        SIMD4<Float>(surface.x, surface.y, surface.z, 0),
        SIMD4<Float>(-north.x, -north.y, -north.z, 0),
        SIMD4<Float>(0, 0, 0, 1)
      )
      let directionalRotation = matrix_float4x4(rotationAbout: surface, by: Float.random(in: -Float.pi..<Float.pi, using: &prng))
      let rotation = directionalRotation * baseRotation
      let transform = rotation * config.correction
      let scale: Float = Float(Double.random(in: config.scale, using: &prng))
      return InstanceUniforms(coordinate: coordinate, transform: transform, scale: scale)
    }
  }
  
  func draw(_ node: Node, in commandEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, terrain: Terrain) {
    let mesh = node.mesh
    
    var uniforms = uniforms
    var terrain = terrain

    commandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: VertexBufferIndex.uniforms.rawValue)
    commandEncoder.setVertexBuffer(instanceUniformsBuffer, offset: 0, index: VertexBufferIndex.instanceUniforms.rawValue)
    commandEncoder.setVertexBytes(&terrain, length: MemoryLayout<Terrain>.stride, index: VertexBufferIndex.terrain.rawValue)
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
                                           indexBufferOffset: indexBuffer.offset,
                                           instanceCount: totalObjects)
    }
  }
}

struct ArbitraryRandomNumberGenerator : RandomNumberGenerator {

    mutating func next() -> UInt64 {
        // GKRandom produces values in [INT32_MIN, INT32_MAX] range; hence we need two numbers to produce 64-bit value.
        let next1 = UInt64(bitPattern: Int64(gkrandom.nextInt()))
        let next2 = UInt64(bitPattern: Int64(gkrandom.nextInt()))
        return next1 ^ (next2 << 32)
    }

    init(seed: UInt64) {
        self.gkrandom = GKMersenneTwisterRandomSource(seed: seed)
    }

    private let gkrandom: GKRandom
}
