// The FLUX.2 VAE decode the product would use: flux2-vae-mlx-swift's row-band decodePackedLatents(_:tile:), exact
// against the untiled decode. Reads packed, bn-normalised latents (B, 128, H/16, W/16) from a safetensors file
// (key "latents"), writes a PNG, prints seconds and MLX's peak.
// usage: VAEDecode <vae-dir> <latents.safetensors> <out.png> [...pairs]   (VAE_DTYPE=bf16 for bfloat16)
import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers
import Flux2VAE

func writePNG(_ chw: MLXArray, _ url: URL) throws {
    let hwc = (clip((chw.asType(.float32) + 1) / 2, min: 0, max: 1) * 255 + 0.5).asType(.uint8).transposed(1, 2, 0)
    eval(hwc)
    let (h, w) = (hwc.dim(0), hwc.dim(1))
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    let rgb = hwc.asArray(UInt8.self)
    for i in 0..<(w * h) { rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2] }
    let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "png", code: 1) }
}

let a = CommandLine.arguments
let dtype: DType = ProcessInfo.processInfo.environment["VAE_DTYPE"] == "bf16" ? .bfloat16 : .float32
let vae = try Flux2VAEWeights.loadVAE(directory: URL(fileURLWithPath: a[1]), dtype: dtype)
var i = 2
while i + 1 < a.count {
    let latents = try loadArrays(url: URL(fileURLWithPath: a[i]))["latents"]!.asType(dtype)
    Memory.peakMemory = 0
    let t = Date()
    let image = vae.decodePackedLatents(latents, tile: .standard)
    eval(image)
    let s = Date().timeIntervalSince(t)
    try writePNG(image[0], URL(fileURLWithPath: a[i + 1]))
    print(String(format: "%@ %dx%d decode %.2f s peak %.2f GB", a[i + 1], image.dim(3), image.dim(2), s, Double(Memory.peakMemory) / 1e9))
    i += 2
}
