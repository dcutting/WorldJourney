import Metal
import MetalKit

class Renderer: NSObject {
    
    let device: MTLDevice
    let view: MTKView
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let commandQueue: MTLCommandQueue
    var frameCounter = 0
    var vertexBuffer: MTLBuffer!
    var vertexCount = 0
    let halfGridWidth = 75
    var surfaceDistance: Float = 50.0

    override init() {
        device = Renderer.makeDevice()!
        view = Renderer.makeView(device: device)
        pipelineState = Renderer.makePipelineState(device: device, metalView: view)
        depthStencilState = Renderer.makeDepthStencilState(device: device)!
        commandQueue = device.makeCommandQueue()!
        super.init()
        view.delegate = self
        (vertexBuffer, vertexCount) = makeVertexBuffer(device: device)
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
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
            else { return }
        
        frameCounter += 1
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        //        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let worldRadius: Float = 1.0
        let frequency: Float = 3.0/worldRadius
        let mountainHeight: Float = worldRadius * 0.02
        let surface: Float = (worldRadius + mountainHeight) * 1.05
        surfaceDistance *= 0.99
        let distance: Float = surface + surfaceDistance
        
        let eye = SIMD3<Float>(0, 0, distance)
        
        let gridWidth = Int32(halfGridWidth * 2)
        
        var uniforms = Uniforms(
            worldRadius: worldRadius,
            frequency: frequency,
            amplitude: mountainHeight,
            gridWidth: gridWidth,
            cameraPosition: eye,
            viewMatrix: makeViewMatrix(eye: eye),
            modelMatrix: makeModelMatrix(),
            projectionMatrix: makeProjectionMatrix()
        )
        
        let dataSize = MemoryLayout<Uniforms>.size
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeVertexBuffer(device: MTLDevice) -> (MTLBuffer, Int) {
        let (data, count) = makeGridMesh(n: halfGridWidth)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeShared])!
        return (buffer, count)
    }
    
    private func makeViewMatrix(eye: SIMD3<Float>) -> float4x4 {
        let at = SIMD3<Float>(0.0, 1.0, 0.0)
        let up = SIMD3<Float>(0.0, 1.0, 0.0)
        return look(at: at, eye: eye, up: up)
    }
    
    private func makeModelMatrix() -> float4x4 {
        let angle: Float = Float(frameCounter) / Float(view.preferredFramesPerSecond) / 10
        let spin = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.6), by: -angle)
        return spin
    }
    
    private func makeProjectionMatrix() -> float4x4 {
        let aspectRatio: Float = Float(view.bounds.width) / Float(view.bounds.height)
        return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.001, farZ: 1000.0)
    }
}
