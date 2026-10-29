import AppKit
import CoreGraphics
import Foundation
import ImageIO

// contact-sheet <out.jpg> <columns> <tile-px> <image>… : the images in a grid, each scaled to fit a tile and labelled
// with its file name (evidence a reader can open, where the full-size PNGs are too big to keep in git).
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 4, let columns = Int(args[1]), let tile = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: contact-sheet <out.jpg> <columns> <tile-px> <image>…\n".utf8))
    exit(2)
}
let files = Array(args[3...])
let label = 18, rows = (files.count + columns - 1) / columns
let width = columns * tile, height = rows * (tile + label)
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for (i, file) in files.enumerated() {
    let col = i % columns, row = i / columns
    let top = height - row * (tile + label)
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let scale = min(Double(tile) / Double(image.width), Double(tile) / Double(image.height))
    let w = Double(image.width) * scale, h = Double(image.height) * scale
    ctx.draw(image, in: CGRect(x: Double(col * tile) + (Double(tile) - w) / 2, y: Double(top - label) - h, width: w, height: h))
    let name = (file as NSString).lastPathComponent.replacingOccurrences(of: "-0.png", with: "")
    (name as NSString).draw(at: NSPoint(x: col * tile + 4, y: top - label + 3),
                            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
}
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
CGImageDestinationFinalize(out)
print("wrote \(args[0]) (\(files.count) images)")
