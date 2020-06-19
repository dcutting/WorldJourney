import Metal
import MetalKit

final class Renderer: NSObject {
    
    let device: MTLDevice
    let view: MTKView
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let commandQueue: MTLCommandQueue
    let onRender: () -> Void

    init(onRender: @escaping () -> Void) {
        device = Renderer.makeDevice()!
        view = Renderer.makeView(device: device)
        pipelineState = Renderer.makePipelineState(device: device, metalView: view)
        depthStencilState = Renderer.makeDepthStencilState(device: device)!
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
    
    private static func makePipelineState(device: MTLDevice, metalView: MTKView) -> MTLRenderPipelineState {
        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
        let vertexProgram = defaultLibrary.makeFunction(name: "michelic_vertex")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        
        return try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }

    private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        onRender()
    }
}
