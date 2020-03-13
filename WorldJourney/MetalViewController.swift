import AppKit
import Metal
import MetalKit

var wireframe = false
var tessellationFactor: Float = 64
var grid = 2

struct Uniforms {
    var worldRadius: Float
    var frequency: Float
    var maxHeight: Float
    var frameCounter: Int16
    var cameraPosition: SIMD3<Float>
    var viewMatrix: float4x4
    var modelMatrix: float4x4
    var projectionMatrix: float4x4
}

class MetalViewController: NSViewController {
    
    var metalContext: MetalContext!
    var frameCounter = 0
    
    var vertexBuffer: MTLBuffer!
    var anglesBuffer: MTLBuffer!
    var quadCount = 0
    
    let halfGridWidth = 9
    
    let worldRadius: Float = 2000
    lazy var frequency: Float = 3.0
    lazy var mountainHeight: Float = 0.05
    lazy var surface: Float = worldRadius * 1.5// + 10.001

    lazy var surfaceDistance: Float = worldRadius * 10
    lazy var distance: Float = surfaceDistance
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
        view = metalContext.view
    }
    
    private func makeVertexBuffer(device: MTLDevice, n: Int, eye: SIMD3<Float>, r: Float, R: Float) -> (MTLBuffer, MTLBuffer, Int) {
        let (data, angles, numQuads) = makeUnitCubeMesh(n: n, eye: eye, r: r, R: R)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeManaged])!
        let anglesBuffer = device.makeBuffer(bytes: angles, length: angles.count*4, options: [.storageModeManaged])!
        return (buffer, anglesBuffer, numQuads)
    }
    
    private func render() {
        
        frameCounter += 1
        surfaceDistance *= 0.99
        distance = surface + surfaceDistance

        let commandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        
        computeTessellationFactors(commandBuffer: commandBuffer)
        tessellateAndRender(commandBuffer: commandBuffer)
        
        commandBuffer.commit()
    }
    
    private func computeTessellationFactors(commandBuffer: MTLCommandBuffer) {
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
        if wireframe {
            renderEncoder.setTriangleFillMode(.lines)
        }
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(metalContext.renderPipelineState)
        renderEncoder.setDepthStencilState(metalContext.depthStencilState)
        
        
        let orbit: Float = distance
        
        let cp: Float = -Float(frameCounter)/500
        let x: Float = orbit * cos(cp)
        let y: Float = 0.0
        let z: Float = orbit * sin(cp)
//        let eye = SIMD3<Float>(x, y, z)
        let at = SIMD3<Float>(0, worldRadius*2, 0)
        let eye = SIMD3<Float>(worldRadius * 0.1, worldRadius * 0.1, orbit)
//        let at = SIMD3<Float>(0, 0, 0)

        let d = distance
        let r = worldRadius
        let R = worldRadius + mountainHeight
        
        let gridWidth = Int16(halfGridWidth * 2)
        
        let modelMatrix = makeModelMatrix()

        var uniforms = Uniforms(
            worldRadius: worldRadius,
            frequency: frequency,
            maxHeight: mountainHeight,
            frameCounter: Int16(frameCounter),
            cameraPosition: eye,
            viewMatrix: makeViewMatrix(eye: eye, at: at),
            modelMatrix: modelMatrix,
            projectionMatrix: makeProjectionMatrix()
        )

        let minGrid = 0
        let maxGrid = 6

        let gridDist: Float = worldRadius * 2
        let f: Float
        let a: Float = d - r
        if a > gridDist {
            f = 1.0
        } else {
            f = a / gridDist
        }
        let gridFactor: Float = 1-(sqrt(sqrt(f)))   // TODO: this should be some log2 formula, or visual difference
//        grid = Int(gridFactor)
        
//        var grid = Int(round(gridFactor * Float(maxGrid - minGrid))) + minGrid
//        print(d, r, gridFactor, grid)

        let modelEye4 = SIMD4<Float>(eye, 1) * simd_transpose(modelMatrix)
        let modelEye = SIMD3<Float>(modelEye4.x, modelEye4.y, modelEye4.z)
        (vertexBuffer, anglesBuffer, quadCount) = makeVertexBuffer(device: metalContext.device, n: grid, eye: modelEye, r: r, R: R)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(anglesBuffer, offset: 0, index: 1)

        let dataSize = MemoryLayout<Uniforms>.size
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 2)
        
        renderEncoder.setVertexTexture(metalContext.noiseTexture, index: 0)
        renderEncoder.setVertexSamplerState(metalContext.noiseSampler, index: 0)
        
        renderEncoder.setTessellationFactorBuffer(metalContext.tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        let patchCount = quadCount
        renderEncoder.drawPatches(numberOfPatchControlPoints: 4, patchStart: 0, patchCount: patchCount, patchIndexBuffer: nil, patchIndexBufferOffset: 0, instanceCount: 1, baseInstance: 0)

        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
    }
    
    private func makeViewMatrix(eye: SIMD3<Float>, at: SIMD3<Float>) -> float4x4 {
        let up = SIMD3<Float>(0.0, 1.0, 0.0)
        let lookAt = look(at: at, eye: eye, up: up)
        let angle = sin(Float(frameCounter) / 90.0) / 4.0
        let angle2 = cos(Float(frameCounter) / 150.0) / 4.0
        let roll = float4x4(rotationAbout: SIMD3<Float>(0.0, 0.0, 1.0), by: angle * 3.1)
        let yaw = float4x4(rotationAbout: SIMD3<Float>(0.0, 1.0, 0.0), by: Float(frameCounter) / 200)
        let pitch = float4x4(rotationAbout: SIMD3<Float>(1.0, 0.0, 0.0), by: -angle)
        return lookAt//roll * pitch * yaw * lookAt
    }
    
    private func makeModelMatrix() -> float4x4 {
        let angle: Float = Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) / 50
        let spin = float4x4(rotationAbout: normalize(SIMD3<Float>(0.3, 1.0, 0.0)), by: angle)
        return spin
    }
    
    private func makeProjectionMatrix() -> float4x4 {
        let aspectRatio: Float = Float(metalContext.view.bounds.width) / Float(metalContext.view.bounds.height)
        return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 15000000.0)
    }
}
