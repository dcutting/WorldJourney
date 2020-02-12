import Metal
import MetalKit

final class MetalContext: NSObject {
    
    let device: MTLDevice
    let view: MTKView
    let renderPipelineState: MTLRenderPipelineState
    let computePipelineState: MTLComputePipelineState
    let depthStencilState: MTLDepthStencilState
    let tessellationFactorsBuffer: MTLBuffer
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
        commandQueue = device.makeCommandQueue()!
        self.onRender = onRender
        super.init()
        view.delegate = self
    }

    private static func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }
    
    private static func makeView(device: MTLDevice) -> MTKView {
        let metalView = MTKView(frame: NSRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0))
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
        vertexDescriptor.layouts[0].stride = 12// MemoryLayout.size(ofValue: dummy)
        
        let fragmentProgram = library.makeFunction(name: "basic_fragment")
        let vertexProgram = library.makeFunction(name: "tessellation_vertex")
        
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
}

extension MetalContext: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        onRender()
    }
}
