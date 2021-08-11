import Foundation

class Solar {
  struct Config {
    var winEnergy: Double
    var loseEnergy: Double
    var initialEnergy: Double
    var terrain: Terrain
  }
  
  enum State {
    case waiting
    case countdown(Countdown)
    case race(Race)
    case win
    case lose
    
    mutating func step(time: TimeInterval, config: Config) {
      switch self {
      case .countdown(let countdown):
        self = countdown.step(time: time, config: config)
      case .race(let race):
        self = race.step(time: time, config: config)
      case .waiting, .win, .lose:
        break
      }
      print(self)
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
    var energy: Double
    
    func step(time: TimeInterval, config: Config) -> State {
      var next = self
      let diff = time - lastTime
      next.lastTime = time
      // TODO: use energy by driving. Gain energy by amount of direct sunlight.
      next.energy -= diff
      if next.energy >= config.winEnergy {
        return .win
      } else if next.energy <= config.loseEnergy {
        return .lose
      }
      return .race(next)
    }
  }
  
  let config: Config
  var state: State
  
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
  
  func step(time: TimeInterval) {
    state.step(time: time, config: config)
  }
}
