import Foundation
import simd

protocol PhysicsBody {
    var position: SIMD3<Float> { get set }
    var mass: Float { get }
}

class PlanetPhysicsBody: PhysicsBody {
    var position = SIMD3<Float>(repeating: 0.0)
    let mass: Float
    
    init(mass: Float) {
        self.mass = mass
    }
}

class AvatarPhysicsBody: PhysicsBody {
    var position = SIMD3<Float>(repeating: 0.0)
    var speed = SIMD3<Float>(repeating: 0.0)
    var acceleration = SIMD3<Float>(repeating: 0.0)
    var yawPitch = SIMD2<Float>(0, 0)
    let mass: Float
    
    init(mass: Float) {
        self.mass = mass
    }
}

class BodySystem {
    var planet: PlanetPhysicsBody
    var avatar: AvatarPhysicsBody
    
    let G: Float = 6.67430e-11
    
    init(planet: PlanetPhysicsBody, avatar: AvatarPhysicsBody) {
        self.planet = planet
        self.avatar = avatar
    }
    
    func update() {
        let m1 = planet.mass
        let m2 = avatar.mass
        let r_2 = distance_squared(planet.position, avatar.position)
        let f: Float = G*m1*m2/r_2
        let v = normalize(planet.position - avatar.position)
        avatar.acceleration += v * f
        avatar.speed += avatar.acceleration
        avatar.position += avatar.speed
        print(avatar.position, avatar.speed, avatar.acceleration, f)
        avatar.acceleration = SIMD3<Float>(repeating: 0.0)
    }
}
