import Foundation
import simd
//import GameController // TODO: use this

protocol PhysicsBody {
    var position: SIMD3<Float> { get set }
    var mass: Float { get }
}

class AvatarPhysicsBody: PhysicsBody {
  var height: Float = 3
  var position = SIMD3<Float>(repeating: 0.0)
  var speed = SIMD3<Float>(repeating: 0.0)
  var acceleration = SIMD3<Float>(repeating: 0.0)
  var rollSpeed: Float = 0
  var yawSpeed: Float = 0
  var area: Float = 1
  var pitchSpeed: Float = 0
  var drawn: Float = 0
  var isDrawing = false

  lazy var maxDrawn: Float = drawAmount * 300
  var drawAmount: Float = 0.004

  var look = SIMD3<Float>(0, 0, 1)
  var up = SIMD3<Float>(0, 1, 0)

  let mass: Float
  
  init(mass: Float) {
    self.mass = mass
  }
  
  func updateDrawing() {
    if !isDrawing, drawn > 0 {
      drawn *= 0.95
      if drawn < 0 { drawn = 0 }
    }
    area = 1
  }
}

class PlanetPhysicsBody: PhysicsBody {
    var position = SIMD3<Float>(repeating: 0.0)
    let mass: Float
    
    init(mass: Float) {
        self.mass = mass
    }
}

class BodySystem {
  var planet: PlanetPhysicsBody
  var avatar: AvatarPhysicsBody
  
  var moveAmount: Float = 0.005
  var turnAmount: Float = 0.0002
  lazy var boostAmount: Float = 0.005
  
  var drawModeOn = false
  
  var scale: Float = 1
  
  var fuel: Float = 100
  
  let G: Float = 6.67430e-11

  init(planet: PlanetPhysicsBody, avatar: AvatarPhysicsBody) {
    self.planet = planet
    self.avatar = avatar
  }
  
  func update(terrain: Terrain) {
    if !drawModeOn && avatar.isDrawing {
      updateDrawing()
    }
    updateDrag(terrain: terrain)
    updateRotation()
    updatePosition()
    if fuel < 0 { moveAmount = 0.0; turnAmount = 0.0; boostAmount = 0.0; }
    drawModeOn = false
    avatar.updateDrawing()
  }
  
  func fix(groundLevel: Float, normal: simd_float3) {
    if length(avatar.position) > groundLevel { return }
    let speed = length(avatar.speed)
    if speed > 5 {
      let ns = normalize(avatar.speed)
      let nn = normalize(normal)
      let similarity = (1.0 + dot(ns, nn)) / 2.0
      let rebound = simd_reflect(ns, nn) * speed * similarity
      avatar.speed = rebound
    } else {
      avatar.speed *= 0.99
    }
    avatar.position = normalize(avatar.position) * groundLevel
  }
  
  func updateRotation() {
    updateRoll()
    updateYaw()
    updatePitch()
  }
  
  func updateRoll() {
    let m = float4x4(rotationAbout: avatar.look, by: avatar.rollSpeed)
    avatar.up = (m * simd_float4(avatar.up, 1)).xyz
  }
  
  func updateYaw() {
    let m = float4x4(rotationAbout: avatar.up, by: avatar.yawSpeed)
    avatar.look = (m * simd_float4(avatar.look, 1)).xyz
  }
  
  func updatePitch() {
    let orth = normalize(cross(normalize(avatar.look), normalize(avatar.up)))
    let m = float4x4(rotationAbout: orth, by: avatar.pitchSpeed)
    avatar.look = (m * simd_float4(avatar.look, 1)).xyz
    avatar.up = (m * simd_float4(avatar.up, 1)).xyz
  }
  
//  func standUpright() {
//    avatar.up = simd_float3(0, 1, 0)
//    if abs(avatar.look.x) < 0.01 && abs(avatar.look.z) < 0.01 {
//      avatar.look = simd_float3(0, 0, 1)
//    } else {
//      avatar.look.y = 0
//      avatar.look = normalize(avatar.look)
//    }
//  }

  func stopRotation() {
    avatar.rollSpeed = 0
    avatar.pitchSpeed = 0
    avatar.yawSpeed = 0
  }

  func updatePosition() {
    let m1 = planet.mass
    let m2 = avatar.mass
    let r_2 = distance_squared(planet.position, avatar.position)
    let f: Float = G*m1*m2/r_2
    let v = normalize(planet.position - avatar.position)

    let a = avatar.acceleration + v * f
    avatar.speed += a
    avatar.position += avatar.speed
    avatar.acceleration = .zero
  }
  
  func updateDrawing() {
    print("*** pow!")
    let d = normalize(avatar.look)
    let v = d * avatar.drawn
    avatar.acceleration += v
    fuel -= avatar.drawn
    turnDown(multiplier: 60)
    avatar.isDrawing = false
  }
  
  func forward() {
    let d = normalize(avatar.look)
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func back() {
    let d = -normalize(avatar.look)
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func boost(scale: Float = 1.0) {
    let d = normalize(avatar.up)
    let v = d * boostAmount * scale
    avatar.acceleration += v
    fuel -= boostAmount
  }
  
//  func fall() {
//    let d = -normalize(avatar.up)
//    let v = d * boostAmount
//    avatar.acceleration += v
//  }
  
//  func strafeAway() {
//    let v = normalize(avatar.position) * moveAmount * boostAmount * 50
//    avatar.acceleration += v
//  }
//
//  func strafeTowards() {
//    let v = normalize(avatar.position) * moveAmount * boostAmount * 50
//    avatar.acceleration -= v
//  }
  
  func strafeDown() {
    let d = -normalize(avatar.up)
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func strafeUp() {
    let d = normalize(avatar.up)
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func strafeLeft() {
    let l = normalize(avatar.look)
    let u = normalize(avatar.up)
    let d = -normalize(cross(l, u))
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func strafeRight() {
    let l = normalize(avatar.look)
    let u = normalize(avatar.up)
    let d = normalize(cross(l, u))
    let v = d * moveAmount
    avatar.acceleration += v
    fuel -= moveAmount
  }
  
  func halt() {
    avatar.speed = .zero
    avatar.acceleration = .zero
    stopRotation()
  }
  
  func turnLeft() {
    avatar.yawSpeed += turnAmount
    fuel -= turnAmount
  }
  
  func turnRight() {
    avatar.yawSpeed -= turnAmount
    fuel -= turnAmount
  }
  
  func turnUp() {
    avatar.pitchSpeed += turnAmount
    fuel -= turnAmount
  }
  
  func turnDown(multiplier: Float = 1) {
    avatar.pitchSpeed -= turnAmount * multiplier
    fuel -= turnAmount
  }
  
  func rollLeft() {
    avatar.rollSpeed -= turnAmount
    fuel -= turnAmount
  }
  
  func rollRight() {
    avatar.rollSpeed += turnAmount
    fuel -= turnAmount
  }
  
  func draw() {
    drawModeOn = true
    if !avatar.isDrawing {
      print("... drawing")
      avatar.isDrawing = true
      avatar.drawn = avatar.drawAmount
    } else {
      avatar.drawn = avatar.maxDrawn * pow(avatar.drawn / avatar.maxDrawn, 0.95)
    }
    if avatar.drawn > avatar.maxDrawn {
      avatar.drawn = avatar.maxDrawn
    }
    print("   \(avatar.drawn)")
    fuel -= avatar.drawAmount
  }

  func updateDrag(terrain: Terrain) {
    let v2: Float = length_squared(avatar.speed)
    guard v2 > 0 else { return }

    let height: Float = length(avatar.position) - terrain.sphereRadius
    let atmosphereHeight: Float = terrain.sphereRadius * 0.35
    var ro_t: Float = height / atmosphereHeight
    if ro_t < 0 { ro_t = 0 }
    if ro_t > 1 { ro_t = 1 }
    ro_t = 1 - ro_t
    
    let ro_m: Float = 0.0293

    let ro: Float = ro_t * ro_m // density of air at 0C is 1.293, TODO: should vary with height?
    let c_d: Float = 0.47 // drag coefficient of a sphere
    let f_d = 0.5 * ro * v2 * c_d * avatar.area

    let direction = normalize(avatar.speed)
//    print("air density: \(ro), height: \(height), force: \(f_d), direction: \(direction)")
    let drag = -direction * f_d
    avatar.acceleration += drag
  }
  
  func airBrake() {
    avatar.area = 10
  }
}
