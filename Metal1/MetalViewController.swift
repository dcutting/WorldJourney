import AppKit
import Metal
import MetalKit

class MetalViewController: NSViewController {
    
    var metalContext: MetalContext!
    var frameCounter = 0
    
    var vertexData: [Float] = [
        0.0, 1.0, 0.0,
        -1.0, -1.0, 0.0,
        1.0, -1.0, 0.0
    ]
    var vertexBuffer: MTLBuffer!
    var vertexCount = 0

    var depthStencilState: MTLDepthStencilState!

    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
        depthStencilState = makeDepthStencilState(device: metalContext.device)
        view = metalContext.view
        (vertexBuffer, vertexCount) = makeVertexBuffer(device: metalContext.device)
    }
    
    private func makeMesh() -> ([Float], Int) {
        var data = [Float]()
        let size: Float = 0.5
        let x = 100
        let y = 100
        for j in (-y/2..<y/2) {
            for i in (-x/2..<x/2) {
                let quad = makeQuad(atX: Float(i) * size, y: Float(j) * size, size: size)
                data.append(contentsOf: quad)
            }
        }
        return (data, x*y*2*3)
    }
    
    private func makeQuad(atX x: Float, y: Float, size: Float) -> [Float] {
        let inset = size
        let a = [ x, y, 0 ]
        let b = [ x + inset, y, 0 ]
        let c = [ x, y + inset, 0 ]
        let d = [ x + inset, y + inset, 0]
        return [ a, b, d, d, c, a ].flatMap { $0 }
    }
    
    private func makeVertexBuffer(device: MTLDevice) -> (MTLBuffer, Int) {
        let (data, count) = makeMesh()
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeShared])!
        return (buffer, count)
    }
    
    private func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
    
    struct Uniforms {
        var viewMatrix: float4x4
        var modelMatrix: float4x4
        var projectionMatrix: float4x4
    }
    
    private func render() {
        guard
            let renderPassDescriptor = metalContext.view.currentRenderPassDescriptor,
            let drawable = metalContext.view.currentDrawable
        else { return }

        frameCounter += 1

        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(metalContext.pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let angle: Float = Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) / 2
        let sink = float4x4(translationBy: SIMD3<Float>(0.0, -10.0, 0.0))
        let lieDown = float4x4(rotationAbout: SIMD3<Float>(1.0, 0.0, 0.0), by: -Float.pi/2)
        let spin = float4x4(rotationAbout: SIMD3<Float>(0.0, 0.0, 1.0), by: angle)
        
        let cameraPosition = SIMD3<Float>(0.0, 0.0, 50.0)
        let viewMatrix = float4x4(translationBy: -cameraPosition);
        
        var uniforms = Uniforms(
            viewMatrix: viewMatrix,
            modelMatrix: sink * lieDown * spin,
            projectionMatrix: float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: 1.3, nearZ: 0.1, farZ: 1000.0))
        
        let dataSize = MemoryLayout<Uniforms>.size
        
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
