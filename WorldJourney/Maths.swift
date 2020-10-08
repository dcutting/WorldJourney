import simd

// https://metalbyexample.com/modern-metal-1/
extension float4x4 {
    init(scaleBy s: Float) {
        self.init(SIMD4<Float>(s, 0, 0, 0),
                  SIMD4<Float>(0, s, 0, 0),
                  SIMD4<Float>(0, 0, s, 0),
                  SIMD4<Float>(0, 0, 0, 1))
    }
 
    init(scaleByX x: Float, y: Float, z: Float) {
        self.init(SIMD4<Float>(x, 0, 0, 0),
                  SIMD4<Float>(0, y, 0, 0),
                  SIMD4<Float>(0, 0, z, 0),
                  SIMD4<Float>(0, 0, 0, 1))
    }
 
    init(rotationAbout axis: SIMD3<Float>, by angleRadians: Float) {
        let x = axis.x, y = axis.y, z = axis.z
        let c = cosf(angleRadians)
        let s = sinf(angleRadians)
        let t = 1 - c
        self.init(SIMD4<Float>( t * x * x + c,     t * x * y + z * s, t * x * z - y * s, 0),
                  SIMD4<Float>( t * x * y - z * s, t * y * y + c,     t * y * z + x * s, 0),
                  SIMD4<Float>( t * x * z + y * s, t * y * z - x * s,     t * z * z + c, 0),
                  SIMD4<Float>(                 0,                 0,                 0, 1))
    }
 
    init(translationBy t: SIMD3<Float>) {
        self.init(SIMD4<Float>(   1,    0,    0, 0),
                  SIMD4<Float>(   0,    1,    0, 0),
                  SIMD4<Float>(   0,    0,    1, 0),
                  SIMD4<Float>(t[0], t[1], t[2], 1))
    }
 
    init(perspectiveProjectionFov fovRadians: Float, aspectRatio aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
 
        let xx = xScale
        let yy = yScale
        let zz = zScale
        let zw = Float(-1)
        let wz = wzScale
 
        self.init(SIMD4<Float>(xx,  0,  0,  0),
                  SIMD4<Float>( 0, yy,  0,  0),
                  SIMD4<Float>( 0,  0, zz, zw),
                  SIMD4<Float>( 0,  0, wz,  0))
    }

  // MARK:- Orthographic matrix
  init(orthoLeft left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
    let X = SIMD4<Float>(2 / (right - left), 0, 0, 0)
    let Y = SIMD4<Float>(0, 2 / (top - bottom), 0, 0)
    let Z = SIMD4<Float>(0, 0, 1 / (far - near), 0)
    let W = SIMD4<Float>((left + right) / (left - right),
                   (top + bottom) / (bottom - top),
                   near / (near - far),
                   1)
    self.init()
    columns = (X, Y, Z, W)
  }
}

// Make a view matrix to point a camera at an object.
func look(at: SIMD3<Float>, eye: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let zaxis = normalize(eye - at)
    let xaxis = normalize(cross(up, zaxis))
    let yaxis = cross(zaxis, xaxis)
    let viewMatrix = float4x4(columns: (simd_float4(xaxis, -dot(xaxis, eye)),
                                        simd_float4(yaxis, -dot(yaxis, eye)),
                                        simd_float4(zaxis, -dot(zaxis, eye)),
                                        simd_float4(0, 0, 0, 1)
        )).transpose
    return viewMatrix
}

func look(direction: SIMD3<Float>, eye: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let zaxis = normalize(-direction)
    let xaxis = normalize(cross(up, zaxis))
    let yaxis = cross(zaxis, xaxis)
    let viewMatrix = float4x4(columns: (simd_float4(xaxis, -dot(xaxis, eye)),
                                        simd_float4(yaxis, -dot(yaxis, eye)),
                                        simd_float4(zaxis, -dot(zaxis, eye)),
                                        simd_float4(0, 0, 0, 1)
        )).transpose
    return viewMatrix
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}

extension SIMD3 where Scalar == Float {
    var xz: SIMD2<Scalar> { SIMD2(x, z) }
}
