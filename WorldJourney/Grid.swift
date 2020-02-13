import Foundation

func makeFractalGridMesh(n: Int) -> ([Float], Int) {
    makeFractalGridMesh(n: n, x: 0.0, y: 0.0, size: 1.0)
}

func makeFractalGridMesh(n: Int, x: Float, y: Float, size: Float) -> ([Float], Int) {
    if n == 0 {
        return (makeQuadMesh(atX: x, y: y, size: size), 2 * 3)
    }
    var data = [Float]()
    let halfSize = size / 2.0
    data.append(contentsOf: makeQuadMesh(atX: x, y: y + halfSize, size: halfSize))
    data.append(contentsOf: makeQuadMesh(atX: x + halfSize, y: y, size: halfSize))
    data.append(contentsOf: makeQuadMesh(atX: x + halfSize, y: y + halfSize, size: halfSize))
    var count = 3 * 2 * 3
    let (next, nextCount) = makeFractalGridMesh(n: n-1, x: x, y: y, size: size/2.0)
    data.append(contentsOf: next)
    count += nextCount
    return (data, count)
}

func makeFoveaMesh(n: Int) -> ([Float], Int) {
    var data = [Float]()
    var count = 0
    let width: Float = 2 * 1.0/Float(n)
    for j in (0..<n) {
        for i in (0..<n) {
            let ip = Float(i) - floor(Float(n)/2.0)
            let jp = Float(j) - floor(Float(n)/2.0)
            let d = sqrtf(Float(ip*ip + jp*jp))
            let k = n - Int(ceilf(d))
            let (mesh, gCount) = makeGridMesh(n: k, x: -1.0 + Float(i) * width, y: -1.0 + Float(j) * width, size: width)
            data.append(contentsOf: mesh)
            count += gCount
        }
    }
    return (data, count)
}

func makeGridMesh(n: Int, x: Float, y: Float, size: Float) -> ([Float], Int) {
    var data = [Float]()
    let width: Float = size / Float(n)
    for j in (0..<n) {
        for i in (0..<n) {
            let xp = Float(i) * width + x
            let yp = Float(j) * width + y
            let quad = makeQuadMesh(atX: xp, y: yp, size: width)
            data.append(contentsOf: quad)
        }
    }
    let numQuads = n*n
    let numTriangles = numQuads*2
    return (data, numTriangles)
}

func makeGridMesh(n: Int) -> ([Float], Int) {
    makeGridMesh(n: n, x: -1, y: -1, size: 2)
}

func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [Float] {
    let inset = size
    let a = [ x, y, 0 ]
    let b = [ x + inset, y, 0 ]
    let c = [ x, y + inset, 0 ]
    let d = [ x + inset, y + inset, 0]
    return [ a, b, d, d, c, a ].flatMap { $0 }
}
