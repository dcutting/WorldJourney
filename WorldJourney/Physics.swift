import PhyKit

class Physics {
  let avatar: PHYRigidBody
  private let planet: PHYRigidBody
  private let universe: PHYWorld
  
  private var chassisShape: PHYCollisionShape!
  private var compound: PHYCollisionShape!
  private var raycaster: PHYDefaultVehicleRaycaster!
  private var vehicle: PHYRaycastVehicle!
  var engineForce: Float = 0.0
  var brakeForce: Float = 10.0
  var steering: Float = 0

  let freeFlying = false

  private var lastTime: TimeInterval!

  private let planetMass: Float = 2e16
  private var moveAmount: Float = 400*5
  private var turnAmount: Float = 50
  
  private var groundCenter = PHYVector3.zero

  private let G: Float = 6.67430e-11

  init() {
    let universe = PHYWorld()
    universe.gravity = .zero
    self.universe = universe

//    let avatarShape = PHYCollisionShapeSphere(radius: 10)
//    avatar = PHYRigidBody(type: .dynamic(mass: 1e2), shape: avatarShape)
//    avatar.continuousCollisionDetectionRadius = 0.1

//    let chassisShape = PHYCollisionShapeBox(width: 1, height: 0.1, length: 2)
//    let chassis = PHYRigidBody(type: .dynamic(mass: 1e3), shape: chassisShape)
//    avatar.restitution = 0
//    avatar.friction = 200
//    avatar.spinningFriction = 200
//    avatar.rollingFriction = 200
//    avatar.angularSleepingThreshold = 0.0
//    avatar.angularDamping = 0.0
//    avatar.linearDamping = 0
//    avatar.linearSleepingThreshold = 0.0
//    let tuning = PHYRaycastVehicleTuning()
//    let raycaster = PHYDefaultVehicleRaycaster(world: universe)
//    let vehicle = PHYRaycastVehicle(chassis: chassis, raycaster: raycaster)
//    chassis.activationState = .disableDeactivation
    
//    self.avatar = chassis//vehicle
//    self.avatarVehicle = vehicle
    
    (chassisShape, compound, avatar, raycaster, vehicle) = Self.setupVehicle(world: universe)
    avatar.continuousCollisionDetectionRadius = 0.000001

    universe.add(avatar)
    universe.add(vehicle)
    
    let blah: Float = 1000
    let planetShape = PHYCollisionShapeBox(width: blah, height: blah, length: blah)
    let planet = PHYRigidBody(type: .static, shape: planetShape)
    self.planet = planet
    universe.add(planet)

    universe.simulationDelegate = self
  }
  
  func updatePlanetGeometry(mesh: [[PHYVector3]]) {
    let geometry = PHYGeometry(mesh: mesh)
    let planetShape = PHYCollisionShapeGeometry(geometry: geometry, type: .concave, margin: 1)
    universe.remove(self.planet)
    self.planet.setCollisionShape(planetShape)
    universe.add(self.planet)
  }
  
  private static func setupVehicle(world: PHYWorld) -> (PHYCollisionShape, PHYCollisionShape, PHYRigidBody, PHYDefaultVehicleRaycaster, PHYRaycastVehicle) {
    let CUBE_HALF_EXTENTS: Float = 2
    let vehicleWidth: Float = 2 * CUBE_HALF_EXTENTS
    let vehicleHeight: Float = 0.5
    let vehicleLength: Float = 4 * CUBE_HALF_EXTENTS

    let transformA = SCNMatrix4Translate(SCNMatrix4Identity, 0, 1, 0).blMatrix
    let chassisShape = PHYCollisionShapeBox(width: vehicleWidth, height: vehicleHeight, length: vehicleLength, transform: transformA)
    let transformB = SCNMatrix4Translate(SCNMatrix4Identity, 0, 0, 0).blMatrix
    let compound = PHYCollisionShapeCompound(collisionShapes: [chassisShape], transform: transformB)
    
    // TODO: need this?
    //         {
    //             btCollisionShape* suppShape = new btBoxShape(btVector3(0.5f, 0.1f, 0.5f));
    //             btTransform suppLocalTrans;
    //             suppLocalTrans.setIdentity();
    //             //localTrans effectively shifts the center of mass with respect to the chassis
    //             suppLocalTrans.setOrigin(btVector3(0, 1.0, 2.5));
    //             compound->addChildShape(suppLocalTrans, suppShape);
    //         }
    
    let chassis = PHYRigidBody(type: .dynamic(mass: 800), shape: compound)
//    chassis.position = PHYVector3(0, 5.5, 0)
    chassis.isSleepingEnabled = false
        
    let raycaster = PHYDefaultVehicleRaycaster(world: world)
    let vehicle = PHYRaycastVehicle(chassis: chassis, raycaster: raycaster)
    
    let connectionHeight: Float = 0.0
    let right = 0
    let up = 1
    let forward = 2
    let wheelDirection = PHYVector3(0, -1, 0)
    let wheelAxle = PHYVector3(1, 0, 0)
    let wheelRadius: Float = 0.3
    let wheelWidth: Float = 0.4
    //        let wheelFriction: Float = 1000.0
    //        let suspensionStiffness: Float = 20.0
    //        let suspensionDamping: Float = 2.3
    //        let suspensionCompression: Float = 4.4
    //        let rollInfluence: Float = 0.1
    let suspensionRestLength: Float = 1.5
    
    vehicle.setCoordinateSystem(rightIndex: right, upIndex: up, forwardIndex: forward)
    
    let connectionPoint0 = PHYVector3(CUBE_HALF_EXTENTS - (0.3 * wheelWidth), connectionHeight, 2 * CUBE_HALF_EXTENTS - wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint0,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: true
    )
    let connectionPoint1 = PHYVector3(-CUBE_HALF_EXTENTS + (0.3 * wheelWidth), connectionHeight, 2 * CUBE_HALF_EXTENTS - wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint1,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: true
    )
    let connectionPoint2 = PHYVector3(-CUBE_HALF_EXTENTS + (0.3 * wheelWidth), connectionHeight, -2 * CUBE_HALF_EXTENTS + wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint2,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: false
    )
    let connectionPoint3 = PHYVector3(CUBE_HALF_EXTENTS - (0.3 * wheelWidth), connectionHeight, -2 * CUBE_HALF_EXTENTS + wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint3,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: false
    )
    //        for wheel in vehicle.wheels {
    //            wheel.suspensionStiffness = suspensionStiffness
    //            wheel.wheelsDampingRelaxation = suspensionDamping
    //            wheel.wheelsDampingCompression = suspensionCompression
    //            wheel.frictionSlip = wheelFriction
    //            wheel.rollInfluence = rollInfluence
    //        }
    
//    universe.add(vehicle)
    
    //      let vehicleShape = SCNBox(width: CGFloat(vehicleWidth), height: CGFloat(vehicleHeight), length: CGFloat(vehicleLength), chamferRadius: 0)
    //      let vehicleNode = SCNNode(geometry: vehicleShape)
    //      let green = SCNMaterial()
    //      green.diffuse.contents = NSColor.green
    //      vehicleShape.materials = [green]
    //      scene.rootNode.addChildNode(vehicleNode)
    //      physicsScene.attach(chassis, to: vehicleNode)
    
    return (chassisShape, compound, chassis, raycaster, vehicle)
  }
  
  func step(time: TimeInterval) {
//    vehicle.apply(engineForce: engineForce, wheelIndex: 0)
//    vehicle.apply(engineForce: engineForce, wheelIndex: 1)
    vehicle.apply(engineForce: engineForce, wheelIndex: 2)
    vehicle.apply(engineForce: engineForce, wheelIndex: 3)
    
    vehicle.set(brake: brakeForce, wheelIndex: 0)
    vehicle.set(brake: brakeForce, wheelIndex: 1)
    vehicle.set(brake: brakeForce, wheelIndex: 2)
    vehicle.set(brake: brakeForce, wheelIndex: 3)

    vehicle.set(steeringValue: steering, wheelIndex: 0)
    vehicle.set(steeringValue: steering, wheelIndex: 1)
    
    steering *= 0.9
    engineForce *= 0.9
    brakeForce *= 0.9
    if brakeForce < 10 {
      brakeForce = 10
    }
    
    applyGravity()
    lastTime = lastTime ?? time
    let physicsTime = time - lastTime
    universe.simulationTime = physicsTime
  }
  
  func applyGravity() {
    let pm = planetMass
    let am = avatar.type.mass
    let pp = planet.position.simd
    let ap = avatar.position.simd
    let r_2 = distance_squared(pp, ap)
    let f: Float = G*pm*am/r_2
    let v = normalize(pp - ap)
    let force = (v * f).phyVector3
    if freeFlying && isFlying {
      avatar.setGravity(.zero)
    } else {
      avatar.setGravity(force)
    }
  }
  
  func setGroundCenter(_ center: PHYVector3) {
    self.groundCenter = center
  }

  func forward() {
    if isFlying {
      applyForce(simd_float3(0, 0, -moveAmount))
    } else {
      engineForce = 25000
    }
  }
  
  var isFlying: Bool {
    let flightAltitude: Float = 40
    return length(avatar.position.simd - groundCenter.simd) > flightAltitude
  }
  
  func driveForward() {
    forward()
  }

  func back() {
    if isFlying {
      applyForce(simd_float3(0, 0, moveAmount))
    } else {
      engineForce = -20000
    }
  }
  
  func driveBack() {
    back()
  }

  func strafeLeft() {
    if isFlying {
      applyForce(simd_float3(-moveAmount, 0, 0))
    }
  }

  func strafeRight() {
    if isFlying {
      applyForce(simd_float3(moveAmount, 0, 0))
    }
  }

  func strafeUp() {
    applyForce(simd_float3(0, moveAmount, 0))
  }

  func strafeDown() {
    applyForce(simd_float3(0, -moveAmount, 0))
  }

  func turnLeft() {
    if isFlying {
      applyTorque(simd_float3(0, turnAmount, 0))
    } else {
      steering -= steeringDamping()
    }
  }
  
  func steerLeft() {
    turnLeft()
  }
  
  func steeringDamping() -> Float {
    let maxAngle: Float = 0.14
    let minAngle: Float = 0.01
    let mps = length(avatar.linearVelocity.simd)
    let gain = mps / 25
    let k = 1 - min(max(0, gain), 1)
    return k * (maxAngle - minAngle) + minAngle
  }

  func turnRight() {
    if isFlying {
      applyTorque(simd_float3(0, -turnAmount, 0))
    } else {
      steering += steeringDamping()
    }
  }
  
  func steerRight() {
    turnRight()
  }

  func turnUp() {
    applyTorque(simd_float3(turnAmount, 0, 0))
  }

  func turnDown() {
    applyTorque(simd_float3(-turnAmount, 0, 0))
  }
  
  func rollLeft() {
    applyTorque(simd_float3(0, 0, turnAmount/2))
  }
  
  func rollRight() {
    applyTorque(simd_float3(0, 0, -turnAmount/2))
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

extension SIMD3 where Scalar == Float {
  var phyVector3: PHYVector3 {
    PHYVector3(x, y, z)
  }
}
