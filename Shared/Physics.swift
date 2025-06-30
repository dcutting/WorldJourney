import PhyKit

class Physics {
  let avatar: PHYRigidBody
  private let planet: PHYRigidBody
  private let universe: PHYWorld
  
  private var chassisShape: PHYCollisionShape!
  private var compound: PHYCollisionShape!
  private var raycaster: PHYDefaultVehicleRaycaster!
  private var vehicle: PHYRaycastVehicle!
  var engineForce: Double = 0.0 {
    didSet {
      forces += engineForce
    }
  }
  var brakeForce: Double = 10.0 {
    didSet {
      forces += brakeForce
    }
  }
  var steering: Double = 0
  let maxSteeringAngle: Double = 0.09
  let minSteeringAngle: Double = 0.01
  let steeringGain: Double = 25
  
  var forcesActive = true
  
  let noGravity: Bool
  let walkThroughWalls = false
  let freeFlying = false
  
  var waterLevel: Double = 1

  private var lastTime: TimeInterval!

  private let planetMass: Double
  var moveMultiplier: Double = 1
  private let baseMoveAmount: Double
  private var moveAmount: Double {
    baseMoveAmount * moveMultiplier
  }
  private var turnAmount: Double = 40
  
  private var groundCenter = PHYVector3.zero

  private let G: Double = 6.67430e-11

  init(planetMass: Double, moveAmount: Double, gravity: Bool) {
    self.planetMass = planetMass
    self.baseMoveAmount = moveAmount
    self.noGravity = !gravity
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
    avatar.continuousCollisionDetectionRadius = 0.00001

    universe.add(avatar)
    universe.add(vehicle)
    
    let blah: Double = 1000
    let planetShape = PHYCollisionShapeBox(width: blah, height: blah, length: blah)
    let planet = PHYRigidBody(type: .static, shape: planetShape)
    self.planet = planet
    universe.add(planet)

    universe.simulationDelegate = self
  }
  
  func updatePlanet(mesh: [[PHYVector3]], waterLevel: Double) {
    self.waterLevel = waterLevel
    let geometry = PHYGeometry(mesh: mesh)
    let planetShape = PHYCollisionShapeGeometry(geometry: geometry, type: .concave, margin: 1)
    universe.remove(self.planet)
    self.planet.setCollisionShape(planetShape)
    if !walkThroughWalls {
      universe.add(self.planet)
    }
  }
  
  private static func setupVehicle(world: PHYWorld) -> (PHYCollisionShape, PHYCollisionShape, PHYRigidBody, PHYDefaultVehicleRaycaster, PHYRaycastVehicle) {
    let CUBE_HALF_EXTENTS: Double = 1.5
    let vehicleWidth: Double = 2 * CUBE_HALF_EXTENTS
    let vehicleHeight: Double = 0.2 * CUBE_HALF_EXTENTS
    let vehicleLength: Double = 4 * CUBE_HALF_EXTENTS

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
    
    let chassis = PHYRigidBody(type: .dynamic(mass: 700), shape: compound)
//    chassis.position = PHYVector3(0, 5.5, 0)
    chassis.isSleepingEnabled = false
        
    let raycaster = PHYDefaultVehicleRaycaster(world: world)
    let vehicle = PHYRaycastVehicle(chassis: chassis, raycaster: raycaster)
    
    let connectionHeight: Double = 0.0
    let right = 0
    let up = 1
    let forward = 2
    let wheelDirection = PHYVector3(0, -1, 0)
    let wheelAxle = PHYVector3(1, 0, 0)
    let wheelRadius: Double = 0.4
    let wheelWidth: Double = 0.4
    //        let wheelFriction: Double = 1000.0
    //        let suspensionStiffness: Double = 20.0
    //        let suspensionDamping: Double = 2.3
    //        let suspensionCompression: Double = 4.4
    //        let rollInfluence: Double = 0.1
    let suspensionRestLength: Double = 1 * CUBE_HALF_EXTENTS
    
    let wheelInsetFactor: Double = 0.3
    
    vehicle.setCoordinateSystem(rightIndex: right, upIndex: up, forwardIndex: forward)
    
    let halfVehicleWidth = vehicleWidth / 2.0
    let halfVehicleLength = vehicleLength / 2.0

    let connectionPoint0 = PHYVector3(halfVehicleWidth - (wheelInsetFactor * wheelWidth), connectionHeight, halfVehicleLength - wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint0,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: true
    )
    let connectionPoint1 = PHYVector3(-halfVehicleWidth + (wheelInsetFactor * wheelWidth), connectionHeight, halfVehicleLength - wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint1,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: true
    )
    let connectionPoint2 = PHYVector3(-halfVehicleWidth + (wheelInsetFactor * wheelWidth), connectionHeight, -halfVehicleLength + wheelRadius)
    vehicle.addWheel(
      connectionPoint: connectionPoint2,
      direction: wheelDirection,
      axle: wheelAxle,
      suspensionRestLength: suspensionRestLength,
      radius: wheelRadius,
      isFrontWheel: false
    )
    let connectionPoint3 = PHYVector3(halfVehicleWidth - (wheelInsetFactor * wheelWidth), connectionHeight, -halfVehicleLength + wheelRadius)
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
    
    //      let vehicleShape = SCNBox(width: CGDouble(vehicleWidth), height: CGDouble(vehicleHeight), length: CGDouble(vehicleLength), chamferRadius: 0)
    //      let vehicleNode = SCNNode(geometry: vehicleShape)
    //      let green = SCNMaterial()
    //      green.diffuse.contents = NSColor.green
    //      vehicleShape.materials = [green]
    //      scene.rootNode.addChildNode(vehicleNode)
    //      physicsScene.attach(chassis, to: vehicleNode)
    
    return (chassisShape, compound, chassis, raycaster, vehicle)
  }
  
  var forces: Double = 0
  
  func step(time: TimeInterval) {
    
    if forcesActive {
      
      if engineForce < 0 {
        vehicle.apply(engineForce: engineForce, wheelIndex: 0)
        vehicle.apply(engineForce: engineForce, wheelIndex: 1)
        vehicle.apply(engineForce: 0, wheelIndex: 2)
        vehicle.apply(engineForce: 0, wheelIndex: 3)
      } else {
        vehicle.apply(engineForce: 0, wheelIndex: 0)
        vehicle.apply(engineForce: 0, wheelIndex: 1)
        vehicle.apply(engineForce: engineForce, wheelIndex: 2)
        vehicle.apply(engineForce: engineForce, wheelIndex: 3)
      }
      
      vehicle.set(brake: brakeForce, wheelIndex: 0)
      vehicle.set(brake: brakeForce, wheelIndex: 1)
      vehicle.set(brake: brakeForce, wheelIndex: 2)
      vehicle.set(brake: brakeForce, wheelIndex: 3)
      
      vehicle.set(steeringValue: steering, wheelIndex: 0)
      vehicle.set(steeringValue: steering, wheelIndex: 1)
      
    } else {
      
      vehicle.apply(engineForce: 0, wheelIndex: 0)
      vehicle.apply(engineForce: 0, wheelIndex: 1)
      vehicle.apply(engineForce: 0, wheelIndex: 2)
      vehicle.apply(engineForce: 0, wheelIndex: 3)
      vehicle.set(brake: brakeForce, wheelIndex: 0)
      vehicle.set(brake: brakeForce, wheelIndex: 1)
      vehicle.set(brake: brakeForce, wheelIndex: 2)
      vehicle.set(brake: brakeForce, wheelIndex: 3)
    }
    
    steering *= 0.9
    engineForce *= 0.9
    brakeForce *= 0.9
    if brakeForce < 10 {
      brakeForce = 10
    }
    
    forces = 0
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
    let f: Double = G*pm*am/r_2
    let v = normalize(pp - ap)
    let force = (v * f).phyVector3
    if noGravity || isSwimming || (freeFlying && isFlying) {
      avatar.setGravity(.zero)
    } else {
      avatar.setGravity(force)
    }
  }
  
  func setGroundCenter(_ center: PHYVector3) {
    self.groundCenter = center
  }

  func forward() {
    if isFreeMovement {
      applyForce(simd_double3(0, 0, -moveAmount))
    } else {
      engineForce = 3000
    }
  }
  
  var isSwimming: Bool {
    length(avatar.position.simd) < Double(waterLevel - 1)
  }
  
  var isFlying: Bool {
    let flightAltitude: Double = 20
    return length(avatar.position.simd - groundCenter.simd) > flightAltitude
  }
  
  var isFreeMovement: Bool {
    isFlying || isSwimming || noGravity
  }
  
  func driveForward() {
    forward()
  }

  func back() {
    if isFreeMovement {
      applyForce(simd_double3(0, 0, moveAmount))
    } else {
      if length(avatar.linearVelocity.simd) < 10 {
        print("reversing")
        engineForce = -6000
      } else {
        print("braking")
        brakeForce = 3000
      }
    }
  }
  
  func driveBack() {
    back()
  }

  func strafeLeft() {
    if isFreeMovement {
      applyForce(simd_double3(-moveAmount, 0, 0))
    }
  }

  func strafeRight() {
    if isFreeMovement {
      applyForce(simd_double3(moveAmount, 0, 0))
    }
  }

  func strafeUp() {
    applyForce(simd_double3(0, moveAmount, 0))
  }

  func strafeDown() {
    applyForce(simd_double3(0, -moveAmount, 0))
  }

  func turnLeft() {
    if isFreeMovement {
      applyTorque(simd_double3(0, turnAmount, 0))
    } else {
      steering -= steeringDamping()
    }
  }
  
  func steerLeft() {
    turnLeft()
  }
  
  func steeringDamping() -> Double {
    let mps = length(avatar.linearVelocity.simd)
    let gain = mps / steeringGain
    let k = 1 - min(max(0, gain), 1)
    return k * (maxSteeringAngle - minSteeringAngle) + minSteeringAngle
  }

  func turnRight() {
    if isFreeMovement {
      applyTorque(simd_double3(0, -turnAmount, 0))
    } else {
      steering += steeringDamping()
    }
  }
  
  func steerRight() {
    turnRight()
  }

  func turnUp() {
    applyTorque(simd_double3(turnAmount, 0, 0))
  }

  func turnDown() {
    applyTorque(simd_double3(-turnAmount, 0, 0))
  }
  
  func rollLeft() {
    applyTorque(simd_double3(0, 0, turnAmount/2))
  }
  
  func rollRight() {
    applyTorque(simd_double3(0, 0, -turnAmount/2))
  }
  
  func halt() {
    avatar.clearForces()
  }

  private func applyForce(_ local: simd_double3) {
    forces += length(local)
    if forcesActive {
      let force = calculateWorldForce(local: local)
      avatar.applyForce(force, impulse: true)
    }
  }
  
  private func applyTorque(_ local: simd_double3) {
    forces += length(local)
    if forcesActive {
      let force = calculateWorldForce(local: local)
      avatar.applyTorque(force, impulse: true)
    }
  }
  
  private func calculateWorldForce(local: simd_double3) -> PHYVector3 {
    // TODO-DC: use motion state instead of reading it from avatar directly?
    let o = avatar.orientation
    let orientationQuat = simd_quaternion(o.x, o.y, o.z, o.w)
    let orientation = simd_double3x3(orientationQuat)
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
  var simd: SIMD3<Double> {
    SIMD3<Double>(x, y, z)
  }
}

extension PHYMatrix4 {
  var simd: double4x4 {
    double4x4(self.scnMatrix) // THIS converts to float.
  }
}

extension SIMD3 where Scalar == Double {
  var phyVector3: PHYVector3 {
    PHYVector3(x, y, z)
  }
}
