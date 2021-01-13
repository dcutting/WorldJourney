import PhyKit

class Physics {
  let avatar: PHYRigidBody
  let planet: PHYRigidBody
  let universe: PHYWorld
  
  var lastTime: TimeInterval!
  
  var moveAmount: Float = 100
  var turnAmount: Float = 1

  init() {
    let avatarShape = PHYCollisionShapeSphere(radius: 1)
    let avatar = PHYRigidBody(type: .dynamic(mass: 1e2), shape: avatarShape)
    avatar.angularSleepingThreshold = 0.05
    avatar.angularDamping = 0.5
//    avatar.restitution = 0.0
//    avatar.spinningFriction = 0
//    avatar.friction = 0
//    avatar.rollingFriction = 0
//    avatar.linearDamping = 0
    self.avatar = avatar
    
    let planetShape = PHYCollisionShapeSphere(radius: 600)
    let planet = PHYRigidBody(type: .static, shape: planetShape)
    self.planet = planet

    let universe = PHYWorld()
    universe.gravity = .zero
    universe.add(avatar)
    universe.add(planet)
    self.universe = universe

    universe.simulationDelegate = self
  }
  
  func step(time: TimeInterval) {
    let planetShape = PHYCollisionShapeSphere(radius: 600)
    universe.remove(self.planet)
    self.planet.collisionShape = planetShape
    universe.add(self.planet)
    lastTime = lastTime ?? time
    let physicsTime = time - lastTime
    universe.simulationTime = physicsTime
  }
  
  func forward() {
    applyForce(simd_float3(0, 0, -moveAmount))
  }

  func back() {
    applyForce(simd_float3(0, 0, moveAmount))
  }

  func strafeLeft() {
    applyForce(simd_float3(-moveAmount, 0, 0))
  }

  func strafeRight() {
    applyForce(simd_float3(moveAmount, 0, 0))
  }

  func strafeUp() {
    applyForce(simd_float3(0, moveAmount, 0))
  }

  func strafeDown() {
    applyForce(simd_float3(0, -moveAmount, 0))
  }

  func turnLeft() {
    applyTorque(simd_float3(0, turnAmount, 0))
  }

  func turnRight() {
    applyTorque(simd_float3(0, -turnAmount, 0))
  }

  func turnUp() {
    applyTorque(simd_float3(turnAmount, 0, 0))
  }

  func turnDown() {
    applyTorque(simd_float3(-turnAmount, 0, 0))
  }
  
  func rollLeft() {
    applyTorque(simd_float3(0, 0, turnAmount))
  }
  
  func rollRight() {
    applyTorque(simd_float3(0, 0, -turnAmount))
  }
  
  func halt() {
    avatar.clearForces()
  }

  private func applyForce(_ local: simd_float3) {
    let force = calculateWorldForce(local: local)
    avatar.applyForce(force, impulse: true)
  }
  
  private func applyTorque(_ local: simd_float3) {
    let force = calculateWorldForce(local: local)
    avatar.applyTorque(force, impulse: true)
  }
  
  private func calculateWorldForce(local: simd_float3) -> PHYVector3 {
    // TODO-DC: use motion state instead of reading it from avatar directly?
    let o = avatar.orientation
    let orientationQuat = simd_quaternion(o.x, o.y, o.z, o.w)
    let orientation = simd_float3x3(orientationQuat)
    let result = orientation * local
    let force = result.phyVector3
    return force
  }
}

extension Physics: PHYWorldSimulationDelegate {
  func physicsWorld(_ physicsWorld: PHYWorld, willSimulateAtTime time: TimeInterval) {
  }
  
  func physicsWorld(_ physicsWorld: PHYWorld, didSimulateAtTime time: TimeInterval) {
  }
}

extension PHYVector3 {
  var simd: SIMD3<Float> {
    SIMD3<Float>(x, y, z)
  }
}

extension PHYMatrix4 {
  var simd: float4x4 {
    float4x4(self.scnMatrix)
  }
}
