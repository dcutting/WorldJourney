import Foundation
import simd

func makeUnitCubeMesh(n: Int) -> ([Float], Int) {
    var quads = [SIMD3<Float>]()
    let width: Float = 2.0 / Float(n)
    let numSides = 6
    for s in (0..<numSides) {
        for j in (0..<n) {
            for i in (0..<n) {
                let xp = Float(i) * width - 1
                let yp = Float(j) * width - 1
                let quad = makeQuadMesh(atX: xp, y: yp, size: width)
                let rotatedQuad = rotate(quad: quad, cubeSide: s)
                quads.append(contentsOf: rotatedQuad)
            }
        }
    }
    let data = quads.map { q -> [Float] in [q.x, q.y, q.z] }.flatMap { $0 }
    let numQuads = n*n*numSides
    let numTriangles = numQuads*2
    print(quads, data, numTriangles)
    return (data, numTriangles)
}

private func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [SIMD2<Float>] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [a, b, d, d, c, a]
}

func rotate(quad: [SIMD2<Float>], cubeSide s: Int) -> [SIMD3<Float>] {
    let rotate: float4x4
    switch (s) {
    case 1:
        rotate = float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: .pi/2)
    case 2:
        rotate = float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: .pi)
    case 3:
        rotate = float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: .pi*3/2)
    case 4:
        rotate = float4x4(rotationAbout: SIMD3<Float>(1, 0, 0), by: .pi/2)
    case 5:
        rotate = float4x4(rotationAbout: SIMD3<Float>(1, 0, 0), by: .pi*3/2)
    default:    // 0
        rotate = float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: 0)
        break;
    }
    let rotatedQuad = quad.map { q -> SIMD3<Float> in
        let r = SIMD4<Float>(q.x, q.y, 1, 1) * rotate
        return SIMD3<Float>(r.x, r.y, r.z)
    }
    return rotatedQuad
}
