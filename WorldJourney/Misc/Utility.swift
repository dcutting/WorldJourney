import MetalKit

func makeTexture(imageName: String, device: MTLDevice) -> MTLTexture {
  let textureLoader = MTKTextureLoader(device: device)
  return try! textureLoader.newTexture(name: imageName, scaleFactor: 1.0, bundle: Bundle.main, options: [.textureStorageMode: NSNumber(integerLiteral: Int(MTLStorageMode.private.rawValue))])
}
