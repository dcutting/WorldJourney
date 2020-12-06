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
  var pitchSpeed: Float = 0

  var look = SIMD3<Float>(0, 0, 1)
  var up = SIMD3<Float>(0, 1, 0)

  let mass: Float
  
  init(mass: Float) {
    self.mass = mass
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
  var turnAmount: Float = 0.0001
  lazy var boostAmount: Float = 0.002
  
  var scale: Float = 1
  
  let G: Float = 6.67430e-11

  init(planet: PlanetPhysicsBody, avatar: AvatarPhysicsBody) {
    self.planet = planet
    self.avatar = avatar
  }
    
  func update() {
    updateRotation()
    updatePosition()
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

//  func airBrake() {
//    let d = normalize(avatar.speed)
//    let v = -d * 10 * moveAmount
//    avatar.acceleration += v
//  }
  
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
  
  func forward() {
    let d = normalize(avatar.look)
    let v = d * moveAmount
    avatar.acceleration += v
  }
  
  func back() {
    let d = -normalize(avatar.look)
    let v = d * moveAmount
    avatar.acceleration += v
  }
  
  func boost(scale: Float = 1.0) {
    let d = normalize(avatar.up)
    let v = d * boostAmount * scale
    avatar.acceleration += v
  }
  
  func fall() {
    let d = -normalize(avatar.up)
    let v = d * boostAmount
    avatar.acceleration += v
  }
  
  func strafeAway() {
    let v = normalize(avatar.position) * moveAmount * boostAmount * 50
    avatar.acceleration += v
  }

  func strafeTowards() {
    let v = normalize(avatar.position) * moveAmount * boostAmount * 50
    avatar.acceleration -= v
  }
  
  func strafeLeft() {
    let l = normalize(avatar.look)
    let u = normalize(avatar.up)
    let d = -normalize(cross(l, u))
    let v = d * moveAmount
    avatar.acceleration += v
  }
  
  func strafeRight() {
    let l = normalize(avatar.look)
    let u = normalize(avatar.up)
    let d = normalize(cross(l, u))
    let v = d * moveAmount
    avatar.acceleration += v
  }
  
  func halt() {
    avatar.speed = .zero
    avatar.acceleration = .zero
    stopRotation()
  }
  
  func turnLeft() {
    avatar.yawSpeed += turnAmount
  }
  
  func turnRight() {
    avatar.yawSpeed -= turnAmount
  }
  
  func turnUp() {
    avatar.pitchSpeed += turnAmount
  }
  
  func turnDown() {
    avatar.pitchSpeed -= turnAmount
  }
  
  func rollLeft() {
    avatar.rollSpeed -= turnAmount
  }
  
  func rollRight() {
    avatar.rollSpeed += turnAmount
  }
}
