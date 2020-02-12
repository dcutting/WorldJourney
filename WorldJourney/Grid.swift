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
