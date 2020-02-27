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
    
    if n == 1 {

        var mesh = [Vertex]()
        var numTris = 0

        let quad = makeQuadMesh(atX: x, y: y, size: width)

        let triA = quad[0]
        let rotatedTriA = rotate(vertices: triA, cubeSide: side)
        numTris += 1
        mesh.append(contentsOf: rotatedTriA)
        
        let triB = quad[1]
        let rotatedTriB = rotate(vertices: triB, cubeSide: side)
        numTris += 1
        mesh.append(contentsOf: rotatedTriB)

        return (convertToFloats(mesh: mesh), numTris)
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

private func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [[SIMD2<Float>]] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [[a, b, d], [d, c, a]]
}

private func makeRectangle(atX x: Float, y: Float, size: Float) -> [SIMD2<Float>] {
    let a = SIMD2<Float>(x, y)
    let b = SIMD2<Float>(x + size, y)
    let c = SIMD2<Float>(x, y + size)
    let d = SIMD2<Float>(x + size, y + size)
    return [a, b, c, d]
}

private func rotate(vertices: [SIMD2<Float>], cubeSide s: Int) -> Triangle {
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
    let rotatedVertices = vertices.map { q -> Vertex in
        let r = SIMD4<Float>(q.x, q.y, 1, 1) * rotate
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
