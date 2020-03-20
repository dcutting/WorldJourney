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
    
    var isWalking = false
    
    let G: Float = 6.67430e-11
    
    init(planet: PlanetPhysicsBody, avatar: AvatarPhysicsBody) {
        self.planet = planet
        self.avatar = avatar
    }
    
    func update(groundLevel: Float) {

        if isWalking {
            if avatar.acceleration.max() > 0 || abs(avatar.acceleration.min()) > 0 {
                avatar.position += avatar.acceleration
                avatar.position = normalize(avatar.position) * groundLevel + 2
            }
            print(".walking: \(avatar.acceleration) \(avatar.position)")
            avatar.speed = simd_float3(repeating: 0)
            avatar.acceleration = simd_float3(repeating: 0)
            return
        }

        let m1 = planet.mass
        let m2 = avatar.mass
        let r_2 = distance_squared(planet.position, avatar.position)
        let f: Float = G*m1*m2/r_2
        let v = normalize(planet.position - avatar.position)
        
        let a = avatar.acceleration + v * f
        let s = avatar.speed + a
        let p = avatar.position + s

        if length(p) < groundLevel + 2 {
            if !isWalking {
                avatar.position = normalize(avatar.position) * groundLevel + 2
            }
            isWalking = true
            return
        }

        avatar.position = p
        avatar.speed = s
        print(avatar.position, avatar.speed, avatar.acceleration, f)
        avatar.acceleration = SIMD3<Float>(repeating: 0.0)
    }
    
    func mouseMoved(deltaX: Int, deltaY: Int) {
        avatar.yawPitch += SIMD2<Float>(Float(-deltaX), Float(-deltaY)) / 500
    }
    
    func forward() {
        if isWalking {
            let pitch = avatar.yawPitch.y
            let yaw = avatar.yawPitch.x
            let m = makeViewMatrix(eye: avatar.position, pitch: pitch, yaw: yaw)
            let u = simd_float4(0, 0, -1, 1)
            let ru = u * m
            let v = simd_float3(ru.x, ru.y, ru.z)
            avatar.acceleration = v * moveAmount
            return
        }
        let m = makeViewMatrix(eye: avatar.position, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let u = simd_float4(0, 0, -1, 1)
        let ru = u * m
        let v = simd_float3(ru.x, ru.y, ru.z)
        avatar.acceleration = v * moveAmount
    }
    
    func back() {
        let m = makeViewMatrix(eye: avatar.position, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let u = simd_float4(0, 0, -1, 1)
        let ru = u * m
        let v = simd_float3(ru.x, ru.y, ru.z)
        avatar.acceleration = v * -moveAmount
    }
    
    func boost() {
        isWalking = false
        let m = makeViewMatrix(eye: avatar.position, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let u = simd_float4(0, -1, 0, 1)
        let ru = u * m
        let v = simd_float3(ru.x, ru.y, ru.z)
        avatar.acceleration = v * -moveAmount
    }
    
    func strafeLeft() {
        let m = makeViewMatrix(eye: avatar.position, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let u = simd_float4(0, 0, -1, 1)
        let ru = u * m
        let v = simd_float3(ru.x, ru.y, ru.z)
        let c = cross(v, SIMD3<Float>(0, 1, 0))
        avatar.acceleration = c * -moveAmount
    }
    
    func strafeRight() {
        let m = makeViewMatrix(eye: avatar.position, pitch: avatar.yawPitch.y, yaw: avatar.yawPitch.x)
        let u = simd_float4(0, 0, -1, 1)
        let ru = u * m
        let v = simd_float3(ru.x, ru.y, ru.z)
        let c = cross(v, SIMD3<Float>(0, 1, 0))
        avatar.acceleration = c * moveAmount
    }
    
    func halt() {
        avatar.speed = SIMD3<Float>(repeating: 0)
    }
}
