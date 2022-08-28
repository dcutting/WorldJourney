import Foundation
import SpriteKit

struct World {
  let sunPosition: SIMD3<Float>
  let physics: Physics
  let terrain: Terrain
}

class Solar {
  struct Config {
    var winEnergy: Float
    var loseEnergy: Float
    var initialEnergy: Float
    var terrain: Terrain
  }
  
  enum State {
    case waiting
    case countdown(Countdown)
    case race(Race)
    case win
    case lose
    
    mutating func step(time: TimeInterval, config: Config, world: World) {
      switch self {
      case .countdown(let countdown):
//        world.physics.forcesActive = false
        self = countdown.step(time: time, config: config)
      case .race(let race):
//        world.physics.forcesActive = true
        self = race.step(time: time, config: config, world: world)
      case .waiting, .win, .lose:
//        world.physics.forcesActive = false
        break
      }
    }
  }

  struct Countdown {
    var initial: TimeInterval
    var counter: Int

    func step(time: TimeInterval, config: Config) -> State {
      let diff = Int(ceil(time - initial))
      let remaining = counter - diff
      if remaining <= 0 {
        return .race(Race(lastTime: time, energy: config.initialEnergy))
      }
      return .countdown(self)
    }
  }
  
  struct Race {
    var lastTime: TimeInterval
    var energy: Float
    var isCharging = false
    
    func step(time: TimeInterval, config: Config, world: World) -> State {
      var next = self
//      let diff = time - lastTime
      next.lastTime = time
      let avatarPosition = world.physics.avatar.position.simd
      let forcesExerted = world.physics.forces * 0.000001
      let energyUsed = forcesExerted
      next.isCharging = isSunVisible(p1: avatarPosition, p2: world.sunPosition, p3: .zero, r: world.terrain.sphereRadius + world.terrain.fractal.amplitude/4)
      let energyGained: Float = next.isCharging ? 0.01 : 0
      next.energy = next.energy - energyUsed + energyGained
      if next.energy >= config.winEnergy {
        return .win
      } else if next.energy <= config.loseEnergy {
        return .lose
      }
      return .race(next)
    }
    
    func isSunVisible(p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, r: Float) -> Bool {
      let d = p2 - p1

      let a = dot(d, d)
      let b = 2.0 * dot(d, p1 - p3)
      let c = dot(p3, p3) + dot(p1, p1) - 2.0 * dot(p3, p1) - r*r
      
      let q = b*b-4*a*c
      return q < 0
    }
  }
  
  let config: Config
  var state: State
  var energyText: String {
    switch state {
    case .race(let race):
      return String(format: "%.2f", race.energy)
    default:
      return ""
    }
  }
  var energyColour: SKColor {
    switch state {
    case .race(let race):
      if race.isCharging {
        return SKColor(ciColor: CIColor.green)
      } else {
        return SKColor(ciColor: CIColor.white)
      }
    default:
      return SKColor(ciColor: CIColor.white)
    }
  }
  
  init(config: Config) {
    self.config = config
    self.state = .waiting
  }

  static func makeGame() -> Solar {
    let config = Config(winEnergy: 100, loseEnergy: 0, initialEnergy: 20, terrain: enceladus)
    return Solar(config: config)
  }

  func start(time: TimeInterval) {
    self.state = .countdown(Countdown(initial: time, counter: 5))
  }
  
  func step(time: TimeInterval, world: World) {
    state.step(time: time, config: config, world: world)
  }
}
