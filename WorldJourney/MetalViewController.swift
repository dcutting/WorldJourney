import AppKit
import Metal
import MetalKit

var moveAmount: Float = 0.3

var wireframe = false
var tessellationFactor: Float = 32
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
    
    var eye = SIMD3<Float>(0, 0, 2500)
    var lookAt = SIMD3<Float>(repeating: 0)
    
    let halfGridWidth = 9
    
    let worldRadius: Float = 2000
    lazy var frequency: Float = 2000.0
    lazy var mountainHeight: Float = 0
    lazy var surface: Float = worldRadius + 65.001

    lazy var surfaceDistance: Float = worldRadius * 20
//    lazy var distance: Float = surfaceDistance
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        metalContext = MetalContext { [weak self] in self?.render() }
        view = metalContext.view
        
        avatar.position = SIMD3<Float>(0, 0, worldRadius * 2)
        avatar.speed = SIMD3<Float>(0, 2, -20)
    }

    let planet = PlanetPhysicsBody(mass: 1e14)
    let avatar = AvatarPhysicsBody(mass: 1e2)
    lazy var bodySystem = BodySystem(planet: planet, avatar: avatar)
    
    func updateBodies() {
        
        bodySystem.update(groundLevel: worldRadius)
        
        eye = avatar.position
        
        if Keyboard.IsKeyPressed(KeyCodes.w) || Keyboard.IsKeyPressed(KeyCodes.upArrow) {
            bodySystem.forward()
        }
        if Keyboard.IsKeyPressed(KeyCodes.s) || Keyboard.IsKeyPressed(KeyCodes.downArrow) {
            bodySystem.back()
        }
        if Keyboard.IsKeyPressed(KeyCodes.a) || Keyboard.IsKeyPressed(KeyCodes.leftArrow) {
            bodySystem.strafeLeft()
        }
        if Keyboard.IsKeyPressed(KeyCodes.d) || Keyboard.IsKeyPressed(KeyCodes.rightArrow) {
            bodySystem.strafeRight()
        }
        if Keyboard.IsKeyPressed(KeyCodes.space) {
            bodySystem.boost()
        }
        if Keyboard.IsKeyPressed(KeyCodes.returnKey) {
            bodySystem.halt()
        }
    }
    
    private func makeVertexBuffer(device: MTLDevice, n: Int, eye: SIMD3<Float>, r: Float, R: Float) -> (MTLBuffer, MTLBuffer, Int) {
        let (data, angles, numQuads) = makeUnitCubeMesh(n: n, eye: eye, r: r, R: R)
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0])
        let buffer = device.makeBuffer(bytes: data, length: dataSize, options: [.storageModeManaged])!
        let anglesBuffer = device.makeBuffer(bytes: angles, length: angles.count*4, options: [.storageModeManaged])!
        return (buffer, anglesBuffer, numQuads)
    }
    
    func mouseMoved(deltaX: Int, deltaY: Int) {
        bodySystem.mouseMoved(deltaX: deltaX, deltaY: deltaY)
    }

    private func render() {
        
        updateBodies()
        
        frameCounter += 1
        surfaceDistance *= 0.99
//        surfaceDistance = worldRadius * 1.1
//        distance = surface + surfaceDistance

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
        
        let distance = length(eye)
        
        let orbit: Float = distance
        
        let cp: Float = -Float(frameCounter)/100
        let x: Float = orbit * cos(cp)
        let y: Float = 0.0
        let z: Float = orbit * sin(cp)
//        let eye = SIMD3<Float>(x, y, z)
//        let eye = SIMD3<Float>(0, 0, orbit)
//        let at = SIMD3<Float>(0, worldRadius*3, 0)
//        let at = SIMD3<Float>(0, 0, 0)

        let d = distance
        let r = worldRadius
        let R = worldRadius + mountainHeight
        
        let gridWidth = Int16(halfGridWidth * 2)
        
        let modelMatrix = makeModelMatrix()
        let viewMatrix = makeViewMatrix(eye: eye, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let projectionMatrix = makeProjectionMatrix()

        var uniforms = Uniforms(
            worldRadius: worldRadius,
            frequency: frequency / worldRadius,
            maxHeight: mountainHeight / worldRadius,
            frameCounter: Int16(frameCounter),
            cameraPosition: eye,
            viewMatrix: viewMatrix,
            modelMatrix: modelMatrix,
            projectionMatrix: projectionMatrix
        )

        let minGrid = 0
        let maxGrid = 3
        
//        let gridDist: Float = worldRadius * 10
//        let f: Float
//        let a: Float = d - r
//        if a > gridDist {
//            f = 1.0
//        } else {
//            f = a / gridDist
//        }
//        var gridFactor: Float = 1-(pow(f, 2))   // TODO: this should be some log2 formula, or visual difference
        
//        var gridFactor: Float = f
//
//        if gridFactor.isNaN { gridFactor = 1.0 }
//        if gridFactor < 0.0 { gridFactor = 0.0 }
//        if gridFactor > 1.0 { gridFactor = 1.0 }
//
//        let grid = Int(round(gridFactor * Float(maxGrid - minGrid))) + minGrid
//        print(d, r, avr, f, gridFactor, grid)

        let modelEye4 = SIMD4<Float>(eye, 1) * simd_transpose(modelMatrix)
        let modelEye = SIMD3<Float>(modelEye4.x, modelEye4.y, modelEye4.z)
        (vertexBuffer, anglesBuffer, quadCount) = makeVertexBuffer(device: metalContext.device, n: grid, eye: modelEye, r: r, R: R)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(anglesBuffer, offset: 0, index: 1)

        let dataSize = MemoryLayout<Uniforms>.size
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 2)
        
        renderEncoder.setVertexTexture(metalContext.noiseTexture, index: 0)
        renderEncoder.setVertexSamplerState(metalContext.noiseSampler, index: 0)
        
        renderEncoder.setFragmentTexture(metalContext.texture, index: 0)
        renderEncoder.setFragmentTexture(metalContext.closeTexture, index: 1)
        renderEncoder.setFragmentSamplerState(metalContext.noiseSampler, index: 0)
        renderEncoder.setTessellationFactorBuffer(metalContext.tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        let patchCount = quadCount
        renderEncoder.drawPatches(numberOfPatchControlPoints: 4, patchStart: 0, patchCount: patchCount, patchIndexBuffer: nil, patchIndexBufferOffset: 0, instanceCount: 1, baseInstance: 0)

        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
    }
    
    private func makeModelMatrix() -> float4x4 {
        let angle: Float = 0//Float(frameCounter) / Float(metalContext.view.preferredFramesPerSecond) / -1000
        let spin = float4x4(rotationAbout: normalize(SIMD3<Float>(1.0, 0.1, 0.3)), by: angle)
        return spin
    }
    
    private func makeProjectionMatrix() -> float4x4 {
        let aspectRatio: Float = Float(metalContext.view.bounds.width) / Float(metalContext.view.bounds.height)
        return float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 1, farZ: 1500000.0)
    }
}

func makeViewMatrix(eye: SIMD3<Float>, pitch: Float, yaw: Float) -> float4x4 {
    let cosPitch = cos(pitch)
    let sinPitch = sin(pitch)
    let cosYaw = cos(yaw)
    let sinYaw = sin(yaw)
    let xaxis = SIMD3<Float>(cosYaw, 0, -sinYaw)
    let yaxis = SIMD3<Float>(sinYaw * sinPitch, cosPitch, cosYaw * sinPitch)
    let zaxis = SIMD3<Float>(sinYaw * cosPitch, -sinPitch, cosPitch * cosYaw)
    
    let viewMatrix = float4x4(rows:[
        simd_float4(xaxis, -dot(xaxis, eye)),
        simd_float4(yaxis, -dot(yaxis, eye)),
        simd_float4(zaxis, -dot(zaxis, eye)),
        simd_float4(0, 0, 0, 1)]
    )
    return viewMatrix
}

/*
     float cosPitch = cos(pitch);
     float sinPitch = sin(pitch);
     float cosYaw = cos(yaw);
     float sinYaw = sin(yaw);
  
     vec3 xaxis = { cosYaw, 0, -sinYaw };
     vec3 yaxis = { sinYaw * sinPitch, cosPitch, cosYaw * sinPitch };
     vec3 zaxis = { sinYaw * cosPitch, -sinPitch, cosPitch * cosYaw };
  
     // Create a 4x4 view matrix from the right, up, forward and eye position vectors
     mat4 viewMatrix = {
         vec4(       xaxis.x,            yaxis.x,            zaxis.x,      0 ),
         vec4(       xaxis.y,            yaxis.y,            zaxis.y,      0 ),
         vec4(       xaxis.z,            yaxis.z,            zaxis.z,      0 ),
         vec4( -dot( xaxis, eye ), -dot( yaxis, eye ), -dot( zaxis, eye ), 1 )
     };
 */

func makeViewMatrix(eye: SIMD3<Float>, at: SIMD3<Float>) -> float4x4 {
    let up = SIMD3<Float>(0.0, 1.0, 0.0)
    return look(at: at, eye: eye, up: up)
}
