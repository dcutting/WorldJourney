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
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 0
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
    erode: 0
  ),
  waterLevel: -2000,
  snowLevel: 800,
  sphereRadius: 200,
  groundColour: SIMD3<Float>(0.2, 0.6, 1),
  skyColour: SIMD3<Float>(0.3, 0.3, 0),
  shininess: 0
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
    erode: 0
  ),
  waterLevel: -1700,
  snowLevel: 800,
  sphereRadius: 500,
  groundColour: SIMD3<Float>(0.7, 0.7, 0.7),
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: -1
)

var choco = Terrain(
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
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 50
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
  skyColour: SIMD3<Float>(0, 0, 0),
  shininess: 5
)
