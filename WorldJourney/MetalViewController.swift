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
    
    let halfGridWidth = 9
    
    let worldRadius: Float = 6300
    lazy var frequency: Float = 3.0/worldRadius
    lazy var mountainHeight: Float = 0
    lazy var surface: Float = worldRadius + 0.001

    lazy var surfaceDistance: Float = worldRadius * 2
    lazy var distance: Float = surfaceDistance
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
//        (vertexBuffer, triangleCount) = makeVertexBuffer(device: metalContext.device)
        view = metalContext.view
    }
    
    private func makeVertexBuffer(device: MTLDevice, eye: SIMD3<Float>, d: Float, r: Float, R: Float) -> (MTLBuffer, Int) {
        let (data, numTriangles) = makeUnitCubeMesh(n: halfGridWidth, eye: eye, d: d, r: r, R: R)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeManaged])!
        return (buffer, numTriangles)
    }
    
    private func render() {
        
        frameCounter += 1
        surfaceDistance *= 0.995
        distance = surface + surfaceDistance

        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        computeTessellationFactors(commandBuffer: commandBuffer)
        tessellateAndRender(commandBuffer: commandBuffer)
        
        commandBuffer.commit()
    }
    
    private func computeTessellationFactors(commandBuffer: MTLCommandBuffer) {
//        let blah = distance / worldRadius
        var tessellationFactor: Float = 64
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(metalContext.computePipelineState)
        commandEncoder.setBytes(&tessellationFactor, length: MemoryLayout.size(ofValue: tessellationFactor), index: 0)
        commandEncoder.setBuffer(metalContext.tessellationFactorsBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        commandEncoder.endEncoding()
    }
    
    private func tessellateAndRender(commandBuffer: MTLCommandBuffer) {
        
        guard
            let renderPassDescriptor = metalContext.view.currentRenderPassDescriptor,
            let drawable = metalContext.view.currentDrawable
        else { return }

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.setRenderPipelineState(metalContext.renderPipelineState)
        renderEncoder.setDepthStencilState(metalContext.depthStencilState)
        
        
        let orbit: Float = distance
        
        let cp: Float = Float(frameCounter)/10000
        let x: Float = orbit * cos(cp)
        let y: Float = 0.0
        let z: Float = orbit * sin(cp)
//        let eye = SIMD3<Float>(x, y, z)
        let at = SIMD3<Float>(0, worldRadius*2, 0)
        let eye = SIMD3<Float>(0, 0, orbit)
//        let at = SIMD3<Float>(0, 0, 0)

        let d = distance
        let r = worldRadius
        let R = worldRadius + mountainHeight
//        print(d, r, R)
        
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

        (vertexBuffer, triangleCount) = makeVertexBuffer(device: metalContext.device, eye: eye, d: d, r: r, R: R)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let dataSize = MemoryLayout<Uniforms>.size
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
        
        renderEncoder.setVertexTexture(metalContext.noiseTexture, index: 0)
        renderEncoder.setVertexSamplerState(metalContext.noiseSampler, index: 0)
        
        renderEncoder.setTessellationFactorBuffer(metalContext.tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        let patchCount = triangleCount
        renderEncoder.drawPatches(numberOfPatchControlPoints: 3, patchStart: 0, patchCount: patchCount, patchIndexBuffer: nil, patchIndexBufferOffset: 0, instanceCount: 1, baseInstance: 0)

        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
    }
    
    private func makeViewMatrix(eye: SIMD3<Float>, at: SIMD3<Float>) -> float4x4 {
        let up = SIMD3<Float>(0.0, 1.0, 0.0)
        let lookAt = look(at: at, eye: eye, up: up)
        let angle = sin(Float(frameCounter) / 90.0) / 4.0
        let angle2 = cos(Float(frameCounter) / 150.0) / 4.0
        let roll = float4x4(rotationAbout: SIMD3<Float>(0.0, 0.0, 1.0), by: angle * 3.1)
        let yaw = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.0), by: angle2 * 1.7)
        let pitch = float4x4(rotationAbout: SIMD3<Float>(1.0, 0.0, 0.0), by: -angle)
        return lookAt// roll * pitch * yaw * lookAt
    }
    
    private func makeModelMatrix() -> float4x4 {
        let angle: Float = 0//Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) / 10000
        let spin = float4x4(rotationAbout: SIMD3<Float>(1.0, 0.0, 0.0), by: angle)
        return spin
    }
    
    private func makeProjectionMatrix() -> float4x4 {
        let aspectRatio: Float = Float(metalContext.view.bounds.width) / Float(metalContext.view.bounds.height)
        return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.0005, farZ: 30000.0)
    }
}
