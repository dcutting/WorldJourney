import Foundation
import simd

typealias Vertex = SIMD3<Float>
typealias Vector = SIMD3<Float>
typealias Triangle = [SIMD3<Float>]

let useWholeMesh = true

func makeUnitCubeMesh(n: Int, eye: Vertex, r: Float, R: Float) -> ([Float], [Float], Int) {
    
    let d2 = length_squared(eye)
    let r2 = pow(r, 2)
    let h2 = d2 - r2
    let s2 = pow(R, 2) - r2
    let m = sqrt(h2 + s2)

    var mesh = [Float]()
    var count = 0

    var angles = [Float]()
    for s in (0..<6) {
        let (subMesh, subCount) = makeUnitSideMesh(n: n, side: s, x: -1, y: -1, width: 2, eye: eye, r: r, R: R, m: m)
        mesh.append(contentsOf: subMesh)
        count += subCount
        let (x_a, y_a) = findAngle(forSide: s)
        for a in (0..<subCount) {
            angles.append(x_a)
            angles.append(y_a)
        }
    }
    
//    print(count/2)
    return (mesh, angles, count)
}

func makeUnitSideMesh(n: Int, side: Int, x: Float, y: Float, width: Float, eye: Vertex, r: Float, R: Float, m: Float) -> ([Float], Int) {

//    let rect = makeRectangle(atX: x, y: y, size: width)
//    let rotatedRect = rotate(vertices: rect, cubeSide: side)
//    let u2 = (width * r) * (width * r)
    let center = SIMD2<Float>(x + width/2, y + width/2)
    let rotatedCenter = rotate(vertices: [center], cubeSide: 0) //TODO: rotation is now done on GPU.
    
    let onSurface = normalize(rotatedCenter[0]) * r
    let d = distance(eye, onSurface)
    let hw = width/2
    let ss = r * sqrt(hw*hw+hw*hw)
    let combinedInfluence = m + ss
    if d > combinedInfluence && !useWholeMesh {
//    guard isPotentiallyVisible(vertices: rotatedCenter, eye: eye, r: r, R: R, m2: m2, u: u2) else {
        return ([], 0)
    }
    
    if n == 0 {
        let quad = makeQuadMesh(atX: x, y: y, size: width)
        let rotated = rotate(vertices: quad, cubeSide: 0) //TODO: rotation is now done on GPU.
        return (convertToFloats(mesh: rotated), 2)
    }

    var mesh = [Float]()
    var count = 0

    let halfWidth = width/2.0
    for j in (0..<2) {
        for i in (0..<2) {
            let px = x + Float(i)*halfWidth
            let py = y + Float(j)*halfWidth
            let (subMesh, subCount) = makeUnitSideMesh(n: n-1, side: side, x: px, y: py, width: halfWidth, eye: eye, r: r, R: R, m: m)
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

private func findAngle(forSide s: Int) -> (Float, Float) {
    switch (s) {
    case 1:
        return (0.0, .pi/2)
    case 2:
        return (0.0, .pi)
    case 3:
        return (0.0, .pi*3/2)
    case 4:
        return (.pi/2, 0.0)
    case 5:
        return (.pi*3/2, 0.0)
    default:    // 0
        return (0.0, 0.0)
    }
}

private func rotate(vertices: [SIMD2<Float>], cubeSide s: Int) -> Triangle {
    let epsilon: Float = 0.00 // Without this the center vertex of some sides flashes..
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

private func isPotentiallyVisible(vertices: [Vertex], eye: Vertex, r: Float, R: Float, m2: Float, u: Float) -> Bool {
//    return true
    // TODO: don't think this shortcut actually works for very mountainous terrain - it crops things it shouldn't.
    let lengths = vertices.map { distance_squared(eye, normalize($0) * r) }
    let allDistant = lengths.allSatisfy { $0 > m2 }
//    let inside = !lengths.allSatisfy { $0 > u }
    return !allDistant// || inside
}
