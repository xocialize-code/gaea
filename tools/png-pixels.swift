import Foundation
import ImageIO
import CoreGraphics
// png-pixels <a.png> <b.png> (tools/acceptance-research.sh): decodes both to non-premultiplied RGBA8 (an RGB image gets alpha 255) and compares.
func rgba(_ path: String) -> (Int, Int, [UInt8]) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)!
    let data = img.dataProvider!.data! as Data
    let (w, h, bpr, bpp) = (img.width, img.height, img.bytesPerRow, img.bitsPerPixel / 8)
    var out = [UInt8](repeating: 255, count: w * h * 4)
    data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
        for y in 0..<h { for x in 0..<w { for c in 0..<min(bpp, 4) { out[(y * w + x) * 4 + c] = p[y * bpr + x * bpp + c] } } }
    }
    return (w, h, out)
}
let a = rgba(CommandLine.arguments[1]), b = rgba(CommandLine.arguments[2])
guard a.0 == b.0, a.1 == b.1 else { print("size differs"); exit(1) }
var diff = 0, maxd = 0
for i in 0..<a.2.count where a.2[i] != b.2[i] { diff += 1; maxd = max(maxd, abs(Int(a.2[i]) - Int(b.2[i]))) }
print(diff == 0 ? "pixels identical" : "pixels differ: \(diff) channel values, max \(maxd)")
exit(diff == 0 ? 0 : 1)
