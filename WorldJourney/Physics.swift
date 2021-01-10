import PhyKit

class Physics {
  let avatar: PHYRigidBody
  let planet: PHYRigidBody
  let universe: PHYWorld
  
  var lastTime: TimeInterval!
  
  var moveAmount: Float = 100

  init() {
    let avatarShape = PHYCollisionShapeSphere(radius: 1)
    let avatar = PHYRigidBody(type: .dynamic(mass: 1e2), shape: avatarShape)
    avatar.restitution = 0.8
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
    lastTime = lastTime ?? time
    let physicsTime = time - lastTime
    universe.simulationTime = physicsTime
  }
  
  func forward() {
    avatar.applyForce(PHYVector3(0, 0, moveAmount), impulse: false)
  }

  func back() {
    avatar.applyForce(PHYVector3(0, 0, -moveAmount), impulse: false)
  }
  
  func turnLeft() {
    let localAxis = PHYVector3Make(0, 0.01, 0)
//    let worldAxis = avatar.transform * localAxis
    avatar.applyTorque(localAxis, impulse: false)
  }
}

extension Physics: PHYWorldSimulationDelegate {
  func physicsWorld(_ physicsWorld: PHYWorld, willSimulateAtTime time: TimeInterval) {
  }
  
  func physicsWorld(_ physicsWorld: PHYWorld, didSimulateAtTime time: TimeInterval) {
    print("p: \(avatar.position), o: \(avatar.orientation), d: \(avatar.orientation.direction)")
  }
}

extension PHYVector3 {
  var simd: SIMD3<Float> {
    SIMD3<Float>(x, y, z)
  }
}
