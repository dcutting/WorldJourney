import AppKit
import Metal
import MetalKit

struct Uniforms {
    var worldRadius: Float
    var frequency: Float
    var amplitude: Float
    var gridWidth: Int16
    var cameraPosition: SIMD3<Float>
    var viewMatrix: float4x4
    var modelMatrix: float4x4
    var projectionMatrix: float4x4
}

class MetalViewController: NSViewController {
    
    var metalContext: MetalContext!
    var frameCounter = 0
    
    var vertexBuffer: MTLBuffer!
    var vertexCount = 0
    
    let halfGridWidth = 250

    var surfaceDistance: Float = 100.0

    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
        view = metalContext.view
        (vertexBuffer, vertexCount) = makeVertexBuffer(device: metalContext.device)
    }
        
    private func makeVertexBuffer(device: MTLDevice) -> (MTLBuffer, Int) {
        let (data, count) = makeGridMesh(n: halfGridWidth)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeShared])!
        return (buffer, count)
    }
    
    private func render() {
        guard
            let renderPassDescriptor = metalContext.view.currentRenderPassDescriptor,
            let drawable = metalContext.view.currentDrawable
        else { return }

        frameCounter += 1

        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
//        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.setRenderPipelineState(metalContext.pipelineState)
        renderEncoder.setDepthStencilState(metalContext.depthStencilState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                
        let worldRadius: Float = 1.0
        let frequency: Float = 3.0/worldRadius
        let mountainHeight: Float = worldRadius * 0.03
        let surface: Float = (worldRadius + mountainHeight) * 1.05
        surfaceDistance *= 0.99
        let distance: Float = surface + surfaceDistance
        
        let eye = SIMD3<Float>(0, 0, distance)

        let gridWidth = Int16(halfGridWidth * 2)
        
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
    
    private func makeViewMatrix(eye: SIMD3<Float>) -> float4x4 {
        let at = SIMD3<Float>(1.0, 1.0, 0.0)
        let up = SIMD3<Float>(0.0, 1.0, 0.0)
        return look(at: at, eye: eye, up: up)
    }
    
    private func makeModelMatrix() -> float4x4 {
        let angle: Float = Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) / 10
        let spin = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.1), by: -angle)
        return spin
    }
    
    private func makeProjectionMatrix() -> float4x4 {
        let aspectRatio: Float = Float(metalContext.view.bounds.width) / Float(metalContext.view.bounds.height)
        return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.001, farZ: 1000.0)
    }
}
