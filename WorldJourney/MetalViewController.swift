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
    var triangleCount = 0
    
    let halfGridWidth = 32
    
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
        (vertexBuffer, triangleCount) = makeVertexBuffer(device: metalContext.device)
    }
    
    private func makeVertexBuffer(device: MTLDevice) -> (MTLBuffer, Int) {
        let (data, numTriangles) = makeGridMesh(n: halfGridWidth)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeManaged])!
        return (buffer, numTriangles)
    }
    
    private func render() {
        
        frameCounter += 1
        
        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        computeTessellationFactors(commandBuffer: commandBuffer)
        tessellateAndRender(commandBuffer: commandBuffer)
        
        commandBuffer.commit()
    }
    
    private func computeTessellationFactors(commandBuffer: MTLCommandBuffer) {
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(metalContext.computePipelineState)
        var edgeFactor: Float = 20
        var insideFactor: Float = 20
        commandEncoder.setBytes(&edgeFactor, length: MemoryLayout.size(ofValue: edgeFactor), index: 0)
        commandEncoder.setBytes(&insideFactor, length: MemoryLayout.size(ofValue: insideFactor), index: 1)
        commandEncoder.setBuffer(metalContext.tessellationFactorsBuffer, offset: 0, index: 2)
        commandEncoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        commandEncoder.endEncoding()
    }
    
    private func tessellateAndRender(commandBuffer: MTLCommandBuffer) {
        
        guard
            let renderPassDescriptor = metalContext.view.currentRenderPassDescriptor,
            let drawable = metalContext.view.currentDrawable
        else { return }

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
//        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.setRenderPipelineState(metalContext.renderPipelineState)
        renderEncoder.setDepthStencilState(metalContext.depthStencilState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let worldRadius: Float = 1.0
        let frequency: Float = 3.0/worldRadius
        let mountainHeight: Float = worldRadius * 0.03
        let surface: Float = (worldRadius + mountainHeight) * 1.05
        surfaceDistance *= 0.99
        let distance: Float = surface + surfaceDistance

        let eye = SIMD3<Float>(0, 0, distance)
        let at = SIMD3<Float>(1.0, 1.0, 0.0)

        let gridWidth = Int16(halfGridWidth * 2)

        var uniforms = Uniforms(
            worldRadius: worldRadius,
            frequency: frequency,
            amplitude: mountainHeight,
            gridWidth: gridWidth,
            cameraPosition: eye,
            viewMatrix: makeViewMatrix(eye: eye, at: at),
            modelMatrix: makeModelMatrix(),
            projectionMatrix: makeProjectionMatrix()
        )

        let dataSize = MemoryLayout<Uniforms>.size
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
        
        renderEncoder.setTessellationFactorBuffer(metalContext.tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        let patchCount = triangleCount
        renderEncoder.drawPatches(numberOfPatchControlPoints: 3, patchStart: 0, patchCount: patchCount, patchIndexBuffer: nil, patchIndexBufferOffset: 0, instanceCount: 1, baseInstance: 0)

        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
    }
    
    private func makeViewMatrix(eye: SIMD3<Float>, at: SIMD3<Float>) -> float4x4 {
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
