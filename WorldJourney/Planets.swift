var mars = Terrain(
  fractal: Fractal(
    octaves: 6,
    frequency: 0.0005,
    amplitude: 500,
    lacunarity: 2.1,
    persistence: 0.3,
    warpFrequency: 0.0,
    warpAmplitude: 0,
    erode: 1
  ),
  waterLevel: -1700,
  snowLevel: 800,
  sphereRadius: 50000,
  groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0)
)

var moonA = Terrain(
  fractal: Fractal(
    octaves: 3,
    frequency: 0.01,
    amplitude: 50,
    lacunarity: 2.1,
    persistence: 0.4,
    warpFrequency: 0.004,
    warpAmplitude: 4,
    erode: 1
  ),
  waterLevel: -1700,
  snowLevel: 30,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0x96/255.0, 0x59/255.0, 0x2F/255.0),
  skyColour: SIMD3<Float>(0, 0, 0)
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
    erode: 1
  ),
  waterLevel: -1700,
  snowLevel: 20,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0x1A/255.0, 0x30/255.0, 0x30/255.0),
  skyColour: SIMD3<Float>(0, 0, 0)
)
