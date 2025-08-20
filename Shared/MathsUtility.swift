import CoreGraphics
import simd

extension double4x4 {
  init(scaleBy s: Double) {
    self.init(SIMD4<Double>(s, 0, 0, 0),
              SIMD4<Double>(0, s, 0, 0),
              SIMD4<Double>(0, 0, s, 0),
              SIMD4<Double>(0, 0, 0, 1))
  }
  
  init(translationBy t: SIMD3<Double>) {
    self.init(SIMD4<Double>(   1,    0,    0, 0),
              SIMD4<Double>(   0,    1,    0, 0),
              SIMD4<Double>(   0,    0,    1, 0),
              SIMD4<Double>(t[0], t[1], t[2], 1))
  }
}

// https://metalbyexample.com/modern-metal-1/
extension float4x4 {
  init(_ m: double4x4) {
    self.init(
      SIMD4<Float>(Float(m.columns.0[0]), Float(m.columns.0[1]), Float(m.columns.0[2]), Float(m.columns.0[3])),
      SIMD4<Float>(Float(m.columns.1[0]), Float(m.columns.1[1]), Float(m.columns.1[2]), Float(m.columns.1[3])),
      SIMD4<Float>(Float(m.columns.2[0]), Float(m.columns.2[1]), Float(m.columns.2[2]), Float(m.columns.2[3])),
      SIMD4<Float>(Float(m.columns.3[0]), Float(m.columns.3[1]), Float(m.columns.3[2]), Float(m.columns.3[3]))
    )
  }

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

  var normalMatrix: float3x3 {
      let upperLeft = float3x3(self[0].xyz, self[1].xyz, self[2].xyz)
      return upperLeft.transpose.inverse
  }
}

extension double4x4 {
  init(rotationAbout axis: SIMD3<Double>, by angleRadians: Double) {
    let x = axis.x, y = axis.y, z = axis.z
    let c = cos(angleRadians)
    let s = sin(angleRadians)
    let t = 1 - c
    self.init(SIMD4<Double>( t * x * x + c,     t * x * y + z * s, t * x * z - y * s, 0),
              SIMD4<Double>( t * x * y - z * s, t * y * y + c,     t * y * z + x * s, 0),
              SIMD4<Double>( t * x * z + y * s, t * y * z - x * s,     t * z * z + c, 0),
              SIMD4<Double>(                 0,                 0,                 0, 1))
  }

  init(perspectiveProjectionFov fovRadians: Double, aspectRatio aspect: Double, nearZ: Double, farZ: Double) {
    let yScale = 1 / tan(fovRadians * 0.5)
    let xScale = yScale / aspect
    let zRange = farZ - nearZ
    let zScale = -(farZ + nearZ) / zRange
    let wzScale = -2 * farZ * nearZ / zRange
    
    let xx = xScale
    let yy = yScale
    let zz = zScale
    let zw = Double(-1)
    let wz = wzScale
    
    self.init(SIMD4<Double>(xx,  0,  0,  0),
              SIMD4<Double>( 0, yy,  0,  0),
              SIMD4<Double>( 0,  0, zz, zw),
              SIMD4<Double>( 0,  0, wz,  0))
  }
}

extension matrix_float4x4 {
  static let identity = matrix_float4x4(diagonal: SIMD4<Float>(repeating: 1))
}

extension matrix_double4x4 {
  static let identity = matrix_double4x4(diagonal: SIMD4<Double>(repeating: 1))
}

// Make a view matrix to point a camera at an object.
func look(at: SIMD3<Double>, eye: SIMD3<Double>, up: SIMD3<Double>) -> double4x4 {
  let zaxis = normalize(eye - at)
  let xaxis = normalize(cross(up, zaxis))
  let yaxis = cross(zaxis, xaxis)
  let viewMatrix = double4x4(columns: (simd_double4(xaxis, -dot(xaxis, eye)),
                                       simd_double4(yaxis, -dot(yaxis, eye)),
                                       simd_double4(zaxis, -dot(zaxis, eye)),
                                       simd_double4(0, 0, 0, 1)
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

func makeProjectionMatrix(w: Double, h: Double, fov: Double, farZ: Double) -> double4x4 {
  double4x4(perspectiveProjectionFov: fov, aspectRatio: w/h, nearZ: 0.1, farZ: farZ)
}

func calculateFieldOfView(monitorHeight: Float, monitorDistance: Float) -> Float {
  // https://steamcommunity.com/sharedfiles/filedetails/?l=german&id=287241027
  2 * (atan(monitorHeight / (monitorDistance * 2)))
}

func calculateFieldOfView(degrees: Double) -> Double {
  // https://andyf.me/fovcalc.html
  return degrees / 360.0 * 2 * Double.pi
}

extension SIMD4 where Scalar == Double {
  var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}

extension SIMD3 where Scalar == Double {
  var xz: SIMD2<Scalar> { SIMD2(x, z) }
}

extension SIMD4 where Scalar == Float {
  var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}

extension SIMD3 where Scalar == Float {
  var xz: SIMD2<Scalar> { SIMD2(x, z) }
}

extension SIMD4 where Scalar == Int32 {
  var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}

extension SIMD3 where Scalar == Int32 {
  var xz: SIMD2<Scalar> { SIMD2(x, z) }
}
