import Foundation
import MLX
import TRELLIS2

// Re-texture an existing UV-unwrapped mesh with TRELLIS.2's shape-conditioned texturing chain.
// Usage: retex <weightsDir> <preparedDir> <resolution 512|1024> <atlasSize> <out.glb> [seed]
// preparedDir holds prep_retex.py's npy files (verts_model, verts_gltf, faces, uvs, pixels_<S>).

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
guard args.count >= 6, let res = Int(args[3]), let atlas = Int(args[4]) else {
    print("usage: retex <weightsDir> <preparedDir> <512|1024> <atlasSize> <out.glb> [seed]"); exit(2)
}
let weights = args[1], prepared = args[2], outPath = args[5]
let seed = args.count > 6 ? UInt64(args[6]) ?? 42 : 42

func npy(_ name: String) throws -> MLXArray { try loadArray(url: URL(fileURLWithPath: "\(prepared)/\(name).npy")) }
func safetensors(_ name: String) throws -> [String: MLXArray] {
    try loadArrays(url: URL(fileURLWithPath: "\(weights)/\(name).safetensors"))
}
func normalization(_ key: String) throws -> (MLXArray, MLXArray) {
    let data = try Data(contentsOf: URL(fileURLWithPath: "\(weights)/normalization.json"))
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let entry = obj[key] as! [String: [Double]]
    return (MLXArray(entry["mean"]!.map(Float.init)), MLXArray(entry["std"]!.map(Float.init)))
}

TRELLIS2Config.fastAttention = true   // bf16 SDPA, as production's CFG-free tex flow
let t0 = Date()

// DINOv3 conditioning from the reference image at the tex flow's resolution.
let dino = DINOv3(weights: try safetensors("dino"))
let cond = dino(try npy("pixels_\(res)"))
let negCond = MLXArray.zeros(cond.shape, dtype: cond.dtype)
MLX.eval(cond)
print("cond \(cond.shape)")

let (shapeMean, shapeStd) = try normalization("shape_slat_normalization")
let (texMean, texStd) = try normalization("tex_slat_normalization")
let pipeline = TexturingPipeline(
    encoderWeights: try safetensors("shape_enc"),
    texDitWeights: try safetensors("tex_flow_\(res)"),
    texDecWeights: try safetensors("tex_dec"),
    shapeMean: shapeMean, shapeStd: shapeStd, texMean: texMean, texStd: texStd)

let faces = try npy("faces").asType(.int32)
let piece = TexturingPipeline.Piece(
    name: "mesh", vertices: try npy("verts_model").asType(.float32), faces: faces, uvs: try npy("uvs").asType(.float32))
let textures = try pipeline.run(pieces: [piece], cond: cond, negCond: negCond,
                                resolution: res, atlasSize: atlas, seed: seed)
let tex = textures[0]
print(String(format: "coverage %.3f", tex.coverage))

// bakeWithUVs writes texel row (1-v)·S; a glTF sampler reads row v·S, so export v flipped.
let bakeUVs = try npy("uvs").asType(.float32)
let exportUVs = MLX.concatenated([bakeUVs[0..., 0..<1], 1 - bakeUVs[0..., 1..<2]], axis: 1)
try GLTFExport.writeGLB(to: URL(fileURLWithPath: outPath),
                        positions: try npy("verts_gltf").asType(.float32), indices: faces,
                        uvs: exportUVs,
                        baseColorRGBA: (tex.rgba, tex.atlasSize, tex.atlasSize))
print(String(format: "wrote %@ in %.1fs", outPath, -t0.timeIntervalSinceNow))
