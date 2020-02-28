import Foundation
import simd

typealias Vertex = SIMD3<Float>
typealias Vector = SIMD3<Float>
typealias Triangle = [SIMD3<Float>]

func makeUnitCubeMesh(n: Int, eye: Vertex, d: Float, r: Float, R: Float) -> ([Float], Int) {
    
    let r2 = pow(r, 2)
    let h2 = pow(d, 2) - r2
    let s2 = pow(R, 2) - r2
    let m2 = h2 + s2

    var mesh = [Float]()
    var count = 0

    for s in (0..<6) {
        let (subMesh, subCount) = makeUnitSideMesh(n: n, side: s, x: -1, y: -1, width: 2, eye: eye, r: r, m: m2)
        mesh.append(contentsOf: subMesh)
        count += subCount
    }
    
    print(count)
    return (mesh, count)
}

func makeUnitSideMesh(n: Int, side: Int, x: Float, y: Float, width: Float, eye: Vertex, r: Float, m: Float) -> ([Float], Int) {

    let rect = makeRectangle(atX: x, y: y, size: width)
    let rotatedRect = rotate(vertices: rect, cubeSide: side)
    let u2 = (width * r) * (width * r)
    guard isPotentiallyVisible(vertices: rotatedRect, eye: eye, r: r, m: m, u: u2) else {
        return ([], 0)
    }
    
    if n == 0 {
        let quad = makeQuadMesh(atX: x, y: y, size: width)
        let rotated = rotate(vertices: quad, cubeSide: side)
        return (convertToFloats(mesh: rotated), 2)
    }

    var mesh = [Float]()
    var count = 0

    let halfWidth = width/2.0
    for j in (0..<2) {
        for i in (0..<2) {
            let px = x + Float(i)*halfWidth
            let py = y + Float(j)*halfWidth
            let (subMesh, subCount) = makeUnitSideMesh(n: n-1, side: side, x: px, y: py, width: halfWidth, eye: eye, r: r, m: m)
            mesh.append(contentsOf: subMesh)
            count += subCount
        }
    }
    
    return (mesh, count)
}

private func convertToFloats(mesh: [Vertex]) -> [Float] {
    mesh.map { q -> [Float] in [q.x, q.y, q.z] }.flatMap { $0 }
}

private func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [SIMD2<Float>] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [a, b, d, d, c, a]
}

private func makeRectangle(atX x: Float, y: Float, size: Float) -> [SIMD2<Float>] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [a, b, c, d]
}

private func rotate(vertices: [SIMD2<Float>], cubeSide s: Int) -> Triangle {
    let epsilon: Float = 0.001 // Without this the center vertex of some sides flashes..
    let rotate: float3x3
    switch (s) {
    case 1:
        rotate = float3x3(rotateY: .pi/2-epsilon)
    case 2:
        rotate = float3x3(rotateY: .pi-epsilon)
    case 3:
        rotate = float3x3(rotateY: .pi*3/2-epsilon)
    case 4:
        rotate = float3x3(rotateX: .pi/2-epsilon)
    case 5:
        rotate = float3x3(rotateX: .pi*3/2-epsilon)
    default:    // 0
        rotate = float3x3(rotateY: 0.0-epsilon)
        break;
    }
    let rotatedVertices = vertices.map { q -> Vertex in
        let r = SIMD3<Float>(q.x, q.y, 1) * rotate
        return Vertex(r.x, r.y, r.z)
    }
    return rotatedVertices
}

private func isPotentiallyVisible(vertices: [Vertex], eye: Vertex, r: Float, m: Float, u: Float) -> Bool {
    // TODO: don't think this shortcut actually works for very mountainous terrain - it crops things it shouldn't.
    let lengths = vertices.map { distance_squared(eye, normalize($0) * r) }
    let allDistant = lengths.allSatisfy { $0 > m }
    let inside = !lengths.allSatisfy { $0 > u }
    return !allDistant || inside
}
