import Foundation
import simd
//import GameController // TODO: use this

class AvatarPhysicsBody {
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

class BodySystem {
  var avatar: AvatarPhysicsBody
  
  var moveAmount: Float = 0.002
  var turnAmount: Float = 0.0005
  lazy var boostAmount: Float = 0.02
  
  var scale: Float = 1
  
  let gravity: Float = 0//-0.009
  
  init(avatar: AvatarPhysicsBody) {
    self.avatar = avatar
  }
    
  func update() {
    updateRotation()
    updatePosition()
  }
  
  func fix(groundLevel: Float, normal: simd_float3) {
    if length(avatar.position) <= groundLevel {
//      if avatar.speed.y < 0 {
//        avatar.speed.y = 0
//      }
//      if length(avatar.speed) > 0.5 {
//        avatar.speed.y += (groundLevel - avatar.position.y) / 2
//      }
//      avatar.position.y = groundLevel
      halt()  // TODO: why doesn't this actually stop.
//      avatar.position *= 1.1
    }
  }
  
  func updateRotation() {
//    updateRoll()
    updateYaw()
    updatePitch()
  }
  
  func updateRoll() {
    let m = float4x4(rotationAbout: avatar.look, by: avatar.rollSpeed)
    avatar.up = (m * simd_float4(avatar.up, 1)).xyz
  }
  
  func updateYaw() {
    let m = float4x4(rotationAbout: simd_float3(0, 1, 0), by: avatar.yawSpeed)
    avatar.look = (m * simd_float4(avatar.look, 1)).xyz
  }
  
  func updatePitch() {
    // TODO: fix gimbal lock when pointing down or up
    let orth = normalize(cross(normalize(avatar.look), normalize(avatar.up)))
    let m = float4x4(rotationAbout: orth, by: avatar.pitchSpeed)
    let lp = (m * simd_float4(avatar.look, 1)).xyz
    if abs(lp.x) > 0.05 || abs(lp.z) > 0.05 {
      avatar.look = lp
    } else {
      avatar.pitchSpeed = 0
    }
  }
  
  func standUpright() {
    avatar.up = simd_float3(0, 1, 0)
    if abs(avatar.look.x) < 0.01 && abs(avatar.look.z) < 0.01 {
      avatar.look = simd_float3(0, 0, 1)
    } else {
      avatar.look.y = 0
      avatar.look = normalize(avatar.look)
    }
  }
  
  func stopRotation() {
    avatar.rollSpeed = 0
    avatar.pitchSpeed = 0
    avatar.yawSpeed = 0
  }
  
  func airBrake() {
    let d = normalize(avatar.speed)
    let v = -d * 10 * moveAmount
    avatar.acceleration += v
  }
  
  func updatePosition() {
    let a = avatar.acceleration * scale + simd_float3(0, gravity, 0)
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
  
  func strafeUp() {
    let v = SIMD3<Float>(0, 0, 1) * moveAmount
    avatar.acceleration += v
  }
  
  func strafeDown() {
    let v = -SIMD3<Float>(0, 0, 1) * moveAmount
    avatar.acceleration += v
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
