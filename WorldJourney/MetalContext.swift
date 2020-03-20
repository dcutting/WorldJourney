import Metal
import MetalKit
import GameplayKit

class GameView: MTKView {}

final class MetalContext: NSObject {
    
    let device: MTLDevice
    let view: GameView
    let renderPipelineState: MTLRenderPipelineState
    let computePipelineState: MTLComputePipelineState
    let depthStencilState: MTLDepthStencilState
    let tessellationFactorsBuffer: MTLBuffer
    let texture: MTLTexture
    let closeTexture: MTLTexture
    let noiseTexture: MTLTexture
    let noiseSampler: MTLSamplerState
    let commandQueue: MTLCommandQueue
    let onRender: () -> Void

    init(onRender: @escaping () -> Void) {
        device = MetalContext.makeDevice()!
        let library = device.makeDefaultLibrary()!
        view = MetalContext.makeView(device: device)
        renderPipelineState = MetalContext.makeRenderPipelineState(device: device, library: library, metalView: view)
        computePipelineState = MetalContext.makeComputePipelineState(device: device, library: library)
        depthStencilState = MetalContext.makeDepthStencilState(device: device)!
        tessellationFactorsBuffer = MetalContext.makeTessellationFactorsBuffer(device: device)!
        texture = MetalContext.loadTexture(device: device, name: "7KPaG_yoPIhRmt8nLyhAztUlVhdpH_LnTAdgRgfvn28")!
        closeTexture = MetalContext.loadTexture(device: device, name: "7KPaG_yoPIhRmt8nLyhAztUlVhdpH_LnTAdgRgfvn28")!
        noiseTexture = MetalContext.makeNoiseTexture(device: device)!
        noiseSampler = MetalContext.makeNoiseSampler(device: device)!
        commandQueue = device.makeCommandQueue()!
        self.onRender = onRender
        super.init()
        view.delegate = self
    }

    private static func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }
    
    private static func makeView(device: MTLDevice) -> GameView {
        let metalView = GameView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
        metalView.device = device
        metalView.preferredFramesPerSecond = 60
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.framebufferOnly = true
        return metalView
    }
    
    private static func makeComputePipelineState(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
        let kernelProgram = library.makeFunction(name: "tessellation_kernel")!
        return try! device.makeComputePipelineState(function: kernelProgram)
    }
    
    private static func makeRenderPipelineState(device: MTLDevice, library: MTLLibrary, metalView: MTKView) -> MTLRenderPipelineState {
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stride = 4*3 // TODO: this is the size of 3 floats in bytes..
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.layouts[1].stepFunction = .perPatch
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stride = 4*2
        
        let fragmentProgram = library.makeFunction(name: "basic_fragment")
        let vertexProgram = library.makeFunction(name: "tessellation_vertex")
//        let vertexProgram = library.makeFunction(name: "basic_vertex")

        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.sampleCount = metalView.sampleCount
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        
        pipelineStateDescriptor.isTessellationFactorScaleEnabled = false
        pipelineStateDescriptor.tessellationFactorFormat = .half
        pipelineStateDescriptor.tessellationControlPointIndexType = .none
        pipelineStateDescriptor.tessellationFactorStepFunction = .constant
        pipelineStateDescriptor.tessellationOutputWindingOrder = .clockwise
        pipelineStateDescriptor.tessellationPartitionMode = .fractionalEven
        pipelineStateDescriptor.maxTessellationFactor = 64

        pipelineStateDescriptor.vertexFunction = vertexProgram
        
        return try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }

    private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
    
    private static func makeTessellationFactorsBuffer(device: MTLDevice) -> MTLBuffer? {
        device.makeBuffer(length: 256, options: .storageModePrivate)
    }
    
    private static func makeNoiseTexture(device: MTLDevice) -> MTLTexture? {
        let dim = 5

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r32Float
        descriptor.width = dim
        descriptor.height = dim
        descriptor.depth = dim
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!

        let noiseSource = GKPerlinNoiseSource(frequency: 50.0, octaveCount: 8, persistence: 0.5, lacunarity: 2.0, seed: 47189)
        let noise = GKNoise(noiseSource)

        var values = [Float]()
        for z in (0..<dim) {
            let noiseMap = GKNoiseMap(noise, size: vector_double2(x: 1.0, y: 1.0), origin: vector_double2(Double(z), Double(z)), sampleCount: vector_int2(Int32(dim), Int32(dim)), seamless: true)
            for y in (0..<dim) {
                for x in (0..<dim) {
                    let n = noiseMap.value(at: vector_int2(Int32(x), Int32(y))) + 1
                    values.append(Float(n))
                }
            }
        }
        let region = MTLRegionMake3D(0, 0, 0, dim, dim, dim)
        texture.replace(region: region, mipmapLevel: 0, slice: 0, withBytes: values, bytesPerRow: dim * MemoryLayout<Float>.size, bytesPerImage: dim * dim * MemoryLayout<Float>.size)
        return texture
    }
    
    private static func makeNoiseSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .nearest
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .mirrorRepeat
        descriptor.tAddressMode = .mirrorRepeat
        return device.makeSamplerState(descriptor: descriptor)
    }
    
    private static func loadTexture(device: MTLDevice, name: String) -> MTLTexture? {
        //        let width = 100
        //        let height = width
        //        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        //        let texture = device.makeTexture(descriptor: descriptor)!
        //        let region = MTLRegionMake2D(0, 0, width, height)
        //        texture.replace(region: region, mipmapLevel: 0, withBytes: rawData, bytesPerRow: bytesPerRow)
        //        return texture
        
        let loader = MTKTextureLoader(device: device)
        return try! loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: nil)
    }
}

extension MetalContext: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        onRender()
    }
}
