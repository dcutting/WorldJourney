import Foundation
import simd

class AvatarPhysicsBody {
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
  
  let gravity: Float = -0.009
  
  init(avatar: AvatarPhysicsBody) {
    self.avatar = avatar
  }
    
  func update() {
    updateRotation()
    updatePosition()
  }
  
  func fix(groundLevel: Float) {
    if avatar.position.y <= groundLevel {
      avatar.position.y = groundLevel
      avatar.speed.y = .zero
    }
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
    avatar.up = -cross(normalize(avatar.look), orth)
  }
  
  func resetOrientation() {
    avatar.up = simd_float3(0, 1, 0)
    if abs(avatar.look.x) < 0.01 && abs(avatar.look.z) < 0.01 {
      avatar.look = simd_float3(0, 0, 1)
    } else {
      avatar.look.y = 0
      avatar.look = normalize(avatar.look)
    }
    avatar.rollSpeed = 0
    avatar.pitchSpeed = 0
    avatar.yawSpeed = 0
  }
  
  func updatePosition() {
    let a = avatar.acceleration + simd_float3(0, gravity, 0)
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
  
  func boost() {
    let d = normalize(avatar.up)
    let v = d * boostAmount
    avatar.acceleration += v
  }
  
  func fall() {
    let d = -normalize(avatar.up)
    let v = d * boostAmount
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
    resetOrientation()
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
