import Foundation
import simd

typealias Vertex = SIMD3<Float>
typealias Vector = SIMD3<Float>
typealias Triangle = [SIMD3<Float>]

func makeUnitCubeMesh(n: Int, eye: Vertex, d: Float, r: Float, R: Float) -> ([Float], Int) {
    var mesh = [Vertex]()
    var numTris = 0
    var notVisible = 0
    let width: Float = 2.0 / Float(n)
    let numSides = 6

    let r2 = pow(r, 2)
    let h = sqrt(pow(d, 2) - r2)
    let s = sqrt(pow(R, 2) - r2)
    let m = h + s
    let u = width * r / 2
//    print("m = \(m), u = \(u)")

    for s in (0..<numSides) {
        for j in (0..<n) {
            for i in (0..<n) {
                let xp = Float(i) * width - 1
                let yp = Float(j) * width - 1
                let quad = makeQuadMesh(atX: xp, y: yp, size: width)

                let triA = quad[0]
                let rotatedTriA = rotate(triangle: triA, cubeSide: s)
                if isPotentiallyVisible(triangle: rotatedTriA, eye: eye, r: r, m: m, u: u) {
                    numTris += 1
                    mesh.append(contentsOf: rotatedTriA)
                } else {
                    notVisible += 1
                }
                
                let triB = quad[1]
                let rotatedTriB = rotate(triangle: triB, cubeSide: s)
                if isPotentiallyVisible(triangle: rotatedTriB, eye: eye, r: r, m: m, u: u) {
                    numTris += 1
                    mesh.append(contentsOf: rotatedTriB)
                } else {
                    notVisible += 1
                }
            }
        }
    }
    let data = mesh.map { q -> [Float] in [q.x, q.y, q.z] }.flatMap { $0 }
    print(numTris, notVisible)
    return (data, numTris)
}

private func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [[SIMD2<Float>]] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [[a, b, d], [d, c, a]]
}

private func rotate(triangle: [SIMD2<Float>], cubeSide s: Int) -> Triangle {
    let rotate: float4x4
    switch (s) {
    case 1:
        rotate = float4x4(rotationAbout: Vector(0, 1, 0), by: .pi/2)
    case 2:
        rotate = float4x4(rotationAbout: Vector(0, 1, 0), by: .pi)
    case 3:
        rotate = float4x4(rotationAbout: Vector(0, 1, 0), by: .pi*3/2)
    case 4:
        rotate = float4x4(rotationAbout: Vector(1, 0, 0), by: .pi/2)
    case 5:
        rotate = float4x4(rotationAbout: Vector(1, 0, 0), by: .pi*3/2)
    default:    // 0
        rotate = float4x4(rotationAbout: Vector(0, 1, 0), by: 0)
        break;
    }
    let rotatedTriangle = triangle.map { q -> Vertex in
        let r = SIMD4<Float>(q.x, q.y, 1, 1) * rotate
        return Vertex(r.x, r.y, r.z)
    }
    return rotatedTriangle
}

private func isPotentiallyVisible(triangle: Triangle, eye: Vertex, r: Float, m: Float, u: Float) -> Bool {
    let lengths = triangle.map { length(eye - normalize($0) * r) }
    let allDistant = lengths.allSatisfy { $0 > m }
    let inTriangle = !lengths.allSatisfy { $0 > u }
    return !allDistant || inTriangle
}
