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

    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
        view = metalContext.view
        vertexBuffer = makeVertexBuffer(device: metalContext.device)
    }
    
    private func makeVertexBuffer(device: MTLDevice) -> MTLBuffer {
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        return device.makeBuffer(bytes: vertexData, length: dataSize, options: [.storageModeShared])!
    }
    
    struct Uniforms {
        var modelMatrix: float4x4
        var projectionMatrix: float4x4
    }
    
    private func render() {
        guard
            let renderPassDescriptor = metalContext.view.currentRenderPassDescriptor,
            let drawable = metalContext.view.currentDrawable
        else { return }

        print(frameCounter)
        frameCounter += 1

        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(metalContext.pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let angle = Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) * 4
        print(angle)
        let translation = float4x4(translationBy: SIMD3<Float>(0.0, 0.0, -5.0))
        let rotation = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.0), by: angle)
        
        var uniforms = Uniforms(
            modelMatrix: translation * rotation,
            projectionMatrix: float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: 1.3, nearZ: 0.1, farZ: 100.0))
        
        let dataSize = MemoryLayout<Uniforms>.size
        
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
