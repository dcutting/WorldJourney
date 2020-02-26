import Foundation
import simd

func makeUnitCubeMesh(n: Int, eye: SIMD3<Float>, d: Float, r: Float, R: Float) -> ([Float], Int) {
    var quads = [SIMD3<Float>]()
    var numQuads = 0
    var notVisible = 0
    let width: Float = 2.0 / Float(n)
    let numSides = 6

    let r2 = pow(r, 2)
    let h = sqrt(pow(d, 2) - r2)
    let s = sqrt(pow(R, 2) - r2)
    let m = h + s
    print("m = \(m)")

    for s in (0..<numSides) {
        for j in (0..<n) {
            for i in (0..<n) {
                let xp = Float(i) * width - 1
                let yp = Float(j) * width - 1
                let quad = makeQuadMesh(atX: xp, y: yp, size: width)    // TODO: individual triangles instead of a quad mean more could be cropped
                let rotatedQuad = rotate(quad: quad, cubeSide: s)
                if isPotentiallyVisible(quad: rotatedQuad, eye: eye, r: r, m: m) {
                    numQuads += 1
                    quads.append(contentsOf: rotatedQuad)
                } else {
                    notVisible += 1
                }
            }
        }
    }
    let data = quads.map { q -> [Float] in [q.x, q.y, q.z] }.flatMap { $0 }
    let numTriangles = numQuads*2
    print(numQuads, notVisible)
    return (data, numTriangles)
}

private func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [SIMD2<Float>] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [a, b, d, d, c, a]
}

private func rotate(quad: [SIMD2<Float>], cubeSide s: Int) -> [SIMD3<Float>] {
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

private func isPotentiallyVisible(quad: [SIMD3<Float>], eye: SIMD3<Float>, r: Float, m: Float) -> Bool {
    return !quad.allSatisfy { v in
        // distance from vertex to eye
        length(eye - normalize(v) * r) > m
    }
}
