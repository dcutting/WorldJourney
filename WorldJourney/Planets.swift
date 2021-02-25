import Foundation
import CryptoKit

var mars = Terrain(
  fractal: Fractal(
    octaves: 6,
    frequency: 0.0005,
    amplitude: 500,
    lacunarity: 2.1,
    persistence: 0.3,
    warpFrequency: 0.0,
    warpAmplitude: 0,
    erode: 1,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 800,
  sphereRadius: 50000,
  groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 0,
  mass: 1_000_000_000
)

var splonk = Terrain(
  fractal: Fractal(
    octaves: 6,
    frequency: 0.00001,
    amplitude: 10,
    lacunarity: 2,
    persistence: 0.5,
    warpFrequency: 0.07,
    warpAmplitude: 0.1,
    erode: 0,
    seed: 1
  ),
  waterLevel: -2000,
  snowLevel: 800,
  sphereRadius: 200,
  groundColour: SIMD3<Float>(0.2, 0.6, 1),
  skyColour: SIMD3<Float>(0.3, 0.3, 0),
  shininess: 0,
  mass: 1_000_000_000
)

var hyperion = Terrain(
  fractal: Fractal(
    octaves: 7,
    frequency: 0.001,
    amplitude: 300,
    lacunarity: 2.0,
    persistence: 0.4,
    warpFrequency: 0.0,
    warpAmplitude: 0,
    erode: 0,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 800,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0.7, 0.7, 0.7),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: -1,
  mass: 1_000_000_000
)

var flat = Terrain(
  fractal: Fractal(
    octaves: 2,
    frequency: 0.005,
    amplitude: 1,
    lacunarity: 2.0,
    persistence: 0.5,
    warpFrequency: 0.01,
    warpAmplitude: 0,
    erode: 1,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 30,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 10,
  mass: 60_000_002_048
)

var choco = Terrain(
  fractal: Fractal(
    octaves: 5,
    frequency: 0.005,
    amplitude: 100,
    lacunarity: 2.1,
    persistence: 0.4,
    warpFrequency: 0.003,
    warpAmplitude: 2,
    erode: 1,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 20,
  sphereRadius: 5000,
  groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 20,
  mass: 200e9
)

var prinky = Terrain(
  fractal: Fractal(
    octaves: 4,
    frequency: 0.005,
    amplitude: 80,
    lacunarity: 2.5,
    persistence: 0.6,
    warpFrequency: 0.0002,
    warpAmplitude: 4,
    erode: 1,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 60,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0x96/255.0, 0x79/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 0,
  mass: 60_000_002_048
)

var enceladus = Terrain(
  fractal: Fractal(
    octaves: 4,
    frequency: 0.01,
    amplitude: 40,
    lacunarity: 2.1,
    persistence: 0.4,
    warpFrequency: 0,
    warpAmplitude: 0,
    erode: 1,
    seed: 1
  ),
  waterLevel: -1700,
  snowLevel: 20,
  sphereRadius: 5000,
  groundColour: SIMD3<Float>(0x1A/255.0, 0x30/255.0, 0x30/255.0),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 5,
  mass: 60_000_002_048
)

var smokey = Terrain(
  fractal: Fractal(
    octaves: 6,
    frequency: 0.004,
    amplitude: 40,
    lacunarity: 2.0,
    persistence: 0.5,
    warpFrequency: 0.01,
    warpAmplitude: 0.5,
    erode: 1,
    seed: 1
  ),
  waterLevel: 10,
  snowLevel: 25,
  sphereRadius: 5000,
  groundColour: SIMD3<Float>(0x1A/255.0, 0x30/255.0, 0x30/255.0) / 5.0,
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 2,
  mass: 60_000_002_048
)

func makeValue<T>(data: SHA256.Digest) -> T {
  data.withUnsafeBytes {
    $0.load(as: T.self)
  }
}

func makeCanonicalKey(from key: String) -> UInt64 {
  let canonical = String(key.lowercased().unicodeScalars.filter {
    CharacterSet.alphanumerics.contains($0)
  })
  guard canonical.count > 0, let raw = canonical.data(using: .utf8) else {
    fatalError("Could not encode key: \(key)")
  }
  let hashedRaw = SHA256.hash(data: raw)
  return makeValue(data: hashedRaw)
}

func g(_ int: UInt64) -> Float {
  var v = int
  let data = Data(bytes: &v, count: MemoryLayout.size(ofValue: v))
  let hashed = SHA256.hash(data: data)
  let h: UInt64 = makeValue(data: hashed)
  return Float(Double(h) / Double(UInt64.max))
}

func b(_ int: UInt64) -> Bool {
  g(int) > 0.5
}

func m(_ x: Float, _ r: ClosedRange<Double>) -> Float {
  Float(simd_mix(r.lowerBound, r.upperBound, Double(x)))
}

func makeRandomPlanet() -> Terrain {
  makePlanet(key: UInt64.random(in: 0...UInt64.max))
}

func makePlanet(key: String) -> Terrain {
  let c = makeCanonicalKey(from: key)
  print("Seeding with 'key'...")
  return makePlanet(key: c)
}

func makePlanet(key c: UInt64) -> Terrain {
  print("   planet ID \(c)")
  
  let maxSeed: Float = 1000

  let frequency: Float = m(g(c >> 1), 0.001...0.01)
  let amplitude: Float = m(g(c >> 2), 5...50)
  let lacunarity: Float = m(g(c >> 3), 1.5...2.5)
  let persistence: Float = m(g(c >> 4), 0.1...0.7)
  let warpFrequency: Float = m(g(c >> 5), 0...0.02)
  let warpAmplitude: Float = m(g(c >> 6), 0...2)
  let erode: Float = m(g(c >> 7), 0.4...3)
  let seed: Int32 = Int32(g(c >> 14) * maxSeed)
  let snowLevel: Float = m(g(c >> 12), 0...50)
  let groundColour = SIMD3<Float>(g(c >> 8), g(c >> 9), g(c >> 10))
  let shininess: Float = b(c >> 13) ? m(g(c >> 11), 0...1000) : 0
  let mass: Float = m(g(c >> 15), 20e9...200e9)
  
  let fractal = Fractal(octaves: 4,
                        frequency: frequency,
                        amplitude: amplitude,
                        lacunarity: lacunarity,
                        persistence: persistence,
                        warpFrequency: warpFrequency,
                        warpAmplitude: warpAmplitude,
                        erode: erode,
                        seed: seed)
  let terrain = Terrain(fractal: fractal,
                        waterLevel: -10000,
                        snowLevel: snowLevel,
                        sphereRadius: 500,
                        groundColour: groundColour,
                        skyColour: SIMD3<Float>(0, 0, 0),
                        shininess: shininess,
                        mass: mass)
  return terrain
}
