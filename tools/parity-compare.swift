// AB-T-0373: compares two TierBench runs (records.json), Gaea's and pixel-agency-image-engine's, record by record.
// Pairs records by suite, operation, item, model and tier; compares each pair's outputs pixel by pixel (ImageIO, RGBA8,
// sRGB) or as text; and sets each group's median warm time beside the other's.
//
//   xcrun swift tools/parity-compare.swift <gaea-run> <engine-run> [--json out.json]
import CoreGraphics
import Foundation
import ImageIO

struct Record: Decodable {
    var suite: String, operation: String, item: String, quality: String?, model: String
    var runMs: Int, warm: Bool
    var outputs: [String]
    var error: String?
}

struct Pixels { var width: Int, height: Int, rgba: [UInt8] }

func pixels(_ url: URL) -> Pixels? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let (w, h) = (image.width, image.height)
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return drawn ? Pixels(width: w, height: h, rgba: rgba) : nil
}

/// How two outputs compare: the same bytes, the same pixels, or the largest channel difference and the PSNR between them.
struct Comparison: Encodable {
    var bytes: Bool, pixels: Bool? = nil, maxDiff: Int? = nil, psnr: Double? = nil, note: String? = nil
}

func compare(_ a: URL, _ b: URL) -> Comparison {
    let (da, db) = (try? Data(contentsOf: a), try? Data(contentsOf: b))
    guard let da, let db else { return Comparison(bytes: false, note: "missing output") }
    if da == db { return Comparison(bytes: true, pixels: true, maxDiff: 0) }
    guard let pa = pixels(a), let pb = pixels(b) else {
        // Text or JSON: compare parsed values, so key order and whitespace don't count.
        let ja = try? JSONSerialization.jsonObject(with: da), jb = try? JSONSerialization.jsonObject(with: db)
        if let ja, let jb { return Comparison(bytes: false, pixels: nil, note: NSDictionary(dictionary: ["v": ja]).isEqual(["v": jb]) ? "same value" : "values differ") }
        return Comparison(bytes: false, note: "not an image")
    }
    guard pa.width == pb.width, pa.height == pb.height else {
        return Comparison(bytes: false, pixels: false, note: "size \(pa.width)×\(pa.height) vs \(pb.width)×\(pb.height)")
    }
    var maxDiff = 0, squared = 0.0
    for i in 0..<pa.rgba.count {
        let d = abs(Int(pa.rgba[i]) - Int(pb.rgba[i]))
        maxDiff = max(maxDiff, d); squared += Double(d * d)
    }
    let mse = squared / Double(pa.rgba.count)
    return Comparison(bytes: false, pixels: maxDiff == 0, maxDiff: maxDiff, psnr: mse == 0 ? .infinity : 10 * log10(255 * 255 / mse))
}

/// records.json when the run has finished, else results.jsonl as far as it has got.
func load(_ run: URL) throws -> [Record] {
    if let data = try? Data(contentsOf: run.appending(path: "records.json")) { return try JSONDecoder().decode([Record].self, from: data) }
    return try String(contentsOf: run.appending(path: "results.jsonl"), encoding: .utf8).split(separator: "\n")
        .map { try JSONDecoder().decode(Record.self, from: Data($0.utf8)) }
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: parity-compare.swift <gaea-run> <engine-run> [--json out.json]"); exit(2) }
let gaeaRun = URL(fileURLWithPath: args[1]), engineRun = URL(fileURLWithPath: args[2])
let jsonOut = args.firstIndex(of: "--json").map { URL(fileURLWithPath: args[$0 + 1]) }
let gaea = try load(gaeaRun), engine = try load(engineRun)

func key(_ r: Record) -> String { [r.suite, r.operation, r.model, r.quality ?? "-", r.item].joined(separator: "|") }
func group(_ r: Record) -> String { [r.suite, r.operation, r.model, r.quality ?? "-"].joined(separator: "|") }
var engineByKey: [String: [Record]] = [:]
for r in engine { engineByKey[key(r), default: []].append(r) }

struct Pair: Encodable {
    var key: String, gaeaMs: Int, engineMs: Int, warm: Bool, outputs: [Comparison], error: String?
}
var pairs: [Pair] = []
var seen: [String: Int] = [:]
for r in gaea {
    let k = key(r); let n = seen[k, default: 0]; seen[k] = n + 1
    guard let others = engineByKey[k], n < others.count else {
        pairs.append(Pair(key: k, gaeaMs: r.runMs, engineMs: -1, warm: r.warm, outputs: [], error: "only on Gaea" + (r.error.map { ": \($0)" } ?? "")))
        continue
    }
    let o = others[n]
    let error = [r.error.map { "Gaea: \($0)" }, o.error.map { "engine: \($0)" }].compactMap { $0 }.joined(separator: "; ")
    let outputs = zip(r.outputs, o.outputs).map { compare(gaeaRun.appending(path: $0), engineRun.appending(path: $1)) }
    pairs.append(Pair(key: k, gaeaMs: r.runMs, engineMs: o.runMs, warm: r.warm && o.warm, outputs: outputs, error: error.isEmpty ? nil : error))
}
let gaeaKeys = Set(gaea.map(key))
let onlyEngine = engine.filter { !gaeaKeys.contains(key($0)) }

// Per group: outputs compared, identical in bytes and in pixels, the worst PSNR, and the median warm times.
func median(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : xs.sorted()[xs.count / 2] }
var order: [String] = []
var groups: [String: [Pair]] = [:]
for (r, p) in zip(gaea, pairs) {
    if groups[group(r)] == nil { order.append(group(r)) }
    groups[group(r), default: []].append(p)
}
print("| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for g in order {
    let ps = groups[g]!
    let ok = ps.filter { $0.error == nil }
    let outs = ok.flatMap(\.outputs)
    let warm = ok.filter(\.warm)
    let gm = median(warm.map(\.gaeaMs)), em = median(warm.map(\.engineMs))
    let psnr = outs.compactMap(\.psnr).filter(\.isFinite).min()
    let maxDiff = outs.compactMap(\.maxDiff).max()
    let ratio = (gm != nil && em != nil && em! > 0) ? String(format: "%.2f", Double(gm!) / Double(em!)) : "—"
    let cols = g.split(separator: "|").map(String.init)
    let errors = ps.compactMap(\.error)
    print("| \(cols.joined(separator: " | ")) | \(ok.count) | \(outs.filter(\.bytes).count)/\(outs.count) | "
          + "\(outs.filter { $0.pixels == true }.count)/\(outs.count) | \(psnr.map { String(format: "%.1f", $0) } ?? (outs.isEmpty ? "—" : "∞")) | "
          + "\(maxDiff.map(String.init) ?? "—") | \(gm.map(String.init) ?? "—") | \(em.map(String.init) ?? "—") | \(ratio) | "
          + "\(errors.isEmpty ? "" : "\(errors.count): \(errors[0].prefix(120))") |")
}
// Routing: the model each engine chose per operation and tier, where the request named none (tiers, edits).
func routes(_ records: [Record]) -> [String: String] {
    var picked: [String: [String]] = [:]
    for r in records where ["tiers", "edits"].contains(r.suite) {
        let k = "\(r.operation) | \(r.quality ?? "default")"
        if !(picked[k]?.contains(r.model) ?? false) { picked[k, default: []].append(r.model + (r.error == nil ? "" : " (error)")) }
    }
    return picked.mapValues { $0.joined(separator: ", ") }
}
let gaeaRoutes = routes(gaea), engineRoutes = routes(engine)
print("\n| Operation | Tier | Gaea | Engine | Same |\n|---|---|---|---|---|")
for k in Set(gaeaRoutes.keys).union(engineRoutes.keys).sorted() {
    let (g, e) = (gaeaRoutes[k] ?? "—", engineRoutes[k] ?? "—")
    print("| \(k) | \(g) | \(e) | \(g == e ? "yes" : "**no**") |")
}
if !onlyEngine.isEmpty {
    print("\nOnly on the engine: " + Dictionary(grouping: onlyEngine, by: group).keys.sorted().joined(separator: ", "))
}
if let jsonOut {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    try encoder.encode(pairs).write(to: jsonOut)
}
