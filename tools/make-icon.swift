#!/usr/bin/env swift
// Gaea.app's icon from one square picture (the artwork Gaea generated, Apps/Gaea/Icon/artwork.png).
//
//   swift tools/make-icon.swift icns <artwork.png> <out.icns> [--zoom 1.0]
//       The macOS icon grid: on a 1024 canvas the body is 824 x 824 with continuous corners (radius 185.4) and a soft
//       shadow under it. Every size from 16 to 1024 is drawn from the artwork, then iconutil packs them.
//   swift tools/make-icon.swift sheet <out.png> <artwork.png>...
//       A contact sheet: each picture as an icon at 256, 64 and 32 points, to judge it at the sizes it is seen at.
//
// --zoom enlarges the artwork inside the body (1.15 crops 15 % off the edges), for a subject drawn too small.
import AppKit
import SwiftUI

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

func load(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("can't read \(path)")
    }
    return image
}

func context(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

/// The artwork as a macOS icon of `size` pixels, drawn into `context` with its lower left corner at `origin`.
func drawIcon(_ art: CGImage, in context: CGContext, at origin: CGPoint, size: CGFloat, zoom: CGFloat) {
    let unit = size / 1024
    let body = CGRect(x: origin.x + 100 * unit, y: origin.y + 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = RoundedRectangle(cornerRadius: 185.4 * unit, style: .continuous).path(in: body).cgPath
    // The template's shadow: 10 px down, 10 px blur, black at 30 % (on the 1024 canvas).
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 10 * unit, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(art, in: body.insetBy(dx: -body.width * (zoom - 1) / 2, dy: -body.height * (zoom - 1) / 2))
    context.restoreGState()
}

func write(_ context: CGContext, to path: String) {
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    do { try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) } catch { fail("\(error)") }
}

var arguments = Array(CommandLine.arguments.dropFirst())
var zoom: CGFloat = 1
if let index = arguments.firstIndex(of: "--zoom"), index + 1 < arguments.count, let value = Double(arguments[index + 1]) {
    zoom = CGFloat(value)
    arguments.removeSubrange(index...index + 1)
}

switch arguments.first {
case "icns" where arguments.count == 3:
    let art = load(arguments[1])
    let out = URL(fileURLWithPath: arguments[2])
    let iconset = FileManager.default.temporaryDirectory.appending(path: "gaea-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let pixels = points * scale
        let canvas = context(pixels, pixels)
        drawIcon(art, in: canvas, at: .zero, size: CGFloat(pixels), zoom: zoom)
        write(canvas, to: iconset.appending(path: "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png").path)
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
    print("wrote \(out.path)")

case "sheet" where arguments.count >= 3:
    let files = Array(arguments.dropFirst(2))
    let columns = min(4, files.count), rows = (files.count + columns - 1) / columns
    let cell = CGSize(width: 380, height: 330)
    let sheet = context(Int(cell.width) * columns, Int(cell.height) * rows)
    sheet.setFillColor(CGColor(srgbRed: 0.17, green: 0.19, blue: 0.21, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
    let graphics = NSGraphicsContext(cgContext: sheet, flipped: false)
    for (index, file) in files.enumerated() {
        let art = load(file)
        let x = CGFloat(index % columns) * cell.width
        let y = CGFloat(rows - 1 - index / columns) * cell.height
        drawIcon(art, in: sheet, at: CGPoint(x: x + 10, y: y + 60), size: 256, zoom: zoom)
        drawIcon(art, in: sheet, at: CGPoint(x: x + 280, y: y + 230), size: 64, zoom: zoom)
        drawIcon(art, in: sheet, at: CGPoint(x: x + 296, y: y + 180), size: 32, zoom: zoom)
        drawIcon(art, in: sheet, at: CGPoint(x: x + 304, y: y + 150), size: 16, zoom: zoom)
        NSGraphicsContext.current = graphics
        let label = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        (label as NSString).draw(at: CGPoint(x: x + 24, y: y + 28), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white,
        ])
        NSGraphicsContext.current = nil
    }
    write(sheet, to: arguments[1])
    print("wrote \(arguments[1])")

default:
    fail("usage: make-icon.swift icns <artwork.png> <out.icns> [--zoom z] | sheet <out.png> <artwork.png>...")
}
