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
    
    let halfGridWidth = 128

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
        let n = halfGridWidth
        let size: Float = 1.0 / Float(n)
        for j in (-n..<n) {
            for i in (-n..<n) {
                let x = Float(i) * size
                let y = Float(j) * size
                let quad = makeQuad(atX: x, y: y, size: size)
                data.append(contentsOf: quad)
            }
        }
        let numQuads = n*n*4
        let numTriangles = numQuads*2
        let numVertices = numTriangles*3
        return (data, numVertices)
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
        var gridWidth: Int16
        var cameraDistance: Float
        var viewMatrix: float4x4
        var modelMatrix: float4x4
        var projectionMatrix: float4x4
    }
    
    var distance: Float = 10.0
    
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
        let spin = float4x4(rotationAbout: SIMD3<Float>(1.0, 0.0, 0.0), by: angle)
        let identity = float4x4(1.0)
        
        let surface: Float = 2
        distance *= 0.995
//        distance = ( sin(Float(frameCounter)/20) + 1.5) * 2
        let surfaceDistance: Float = surface + distance
        let cameraPosition = SIMD3<Float>(0.0, 0.0, surfaceDistance);
        let viewMatrix = float4x4(translationBy: -cameraPosition);
        
        var uniforms = Uniforms(
            gridWidth: Int16(halfGridWidth * 2),
            cameraDistance: surfaceDistance,
            viewMatrix: viewMatrix,
            modelMatrix: identity,//sink * lieDown * spin,
            projectionMatrix: float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: 1.3, nearZ: 0.1, farZ: 1000.0))
        
        let dataSize = MemoryLayout<Uniforms>.size
        
        renderEncoder.setVertexBytes(&uniforms, length: dataSize, index: 1)
//        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
