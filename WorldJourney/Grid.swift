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

func makeGridMesh(n: Int) -> ([Float], Int) {
    var data = [Float]()
    let size: Float = 1.0 / Float(n)
    for j in (-n..<n) {
        for i in (-n..<n) {
            let x = Float(i) * size
            let y = Float(j) * size
            let quad = makeQuadMesh(atX: x, y: y, size: size)
            data.append(contentsOf: quad)
        }
    }
    let numQuads = n*n*4
    let numTriangles = numQuads*2
    let numVertices = numTriangles*3
    return (data, numVertices)
}

func makeQuadMesh(atX x: Float, y: Float, size: Float) -> [Float] {
    let inset = size
    let a = [ x, y, 0 ]
    let b = [ x + inset, y, 0 ]
    let c = [ x, y + inset, 0 ]
    let d = [ x + inset, y + inset, 0]
    return [ a, b, d, d, c, a ].flatMap { $0 }
}