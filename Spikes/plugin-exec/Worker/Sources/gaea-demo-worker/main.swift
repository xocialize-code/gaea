import Foundation
import MLX

// Protocol (one JSON object per line):
//   worker → host  {"type":"hello", ...}            once, at start
//   host → worker  {"id":"1","op":"demo.matmul","params":{"n":4096,"iterations":40,"holdBytes":0}}
//   worker → host  {"type":"progress","id":"1","step":3,"of":40}
//   worker → host  {"type":"result","id":"1","output":{...}}  or {"type":"error","id":"1","message":"..."}
//   host → worker  {"op":"cancel","target":"1"}  ·  {"op":"shutdown"}
// Logs go to stderr so stdout stays protocol-only.

let out = FileHandle.standardOutput
let outLock = NSLock()
func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    outLock.lock(); out.write(data); out.write(Data([0x0A])); outLock.unlock()
}

final class CancelFlags: @unchecked Sendable {
    private var ids = Set<String>(); private let lock = NSLock()
    func cancel(_ id: String) { lock.lock(); ids.insert(id); lock.unlock() }
    func isCancelled(_ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(id) }
}
let cancels = CancelFlags()
let work = DispatchQueue(label: "gaea.worker.run") // one job at a time, like Gaea's heavy slot

let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
emit([
    "type": "hello", "protocol": 1, "plugin": "com.xocialize.gaea.demo", "version": "0.1.0",
    "pid": Int(getpid()), "operations": ["demo.matmul"],
    "executable": exe.path, "mainBundle": Bundle.main.bundleURL.path,
    "mainResources": Bundle.main.resourceURL?.path ?? "",
])

func runMatmul(id: String, params: [String: Any]) {
    let n = params["n"] as? Int ?? 2048
    let iterations = params["iterations"] as? Int ?? 10
    let holdBytes = params["holdBytes"] as? Int ?? 0
    let start = Date()
    // Optional resident allocation, so the host can watch footprint rise and fall.
    var hold: MLXArray? = nil
    if holdBytes > 0 { hold = MLXArray.zeros([holdBytes / 4], type: Float.self) + 1; eval(hold!) }
    let a = MLXRandom.normal([n, n]), b = MLXRandom.normal([n, n])
    var c = a
    for step in 1...iterations {
        if cancels.isCancelled(id) { emit(["type": "error", "id": id, "code": "cancelled", "message": "cancelled at step \(step)"]); return }
        c = matmul(c, b) / Float(n).squareRoot()
        eval(c)
        emit(["type": "progress", "id": id, "step": step, "of": iterations])
    }
    let checksum = c.sum().item(Float.self)
    let heldSum = hold.map { $0.sum().item(Float.self) } ?? 0
    emit(["type": "result", "id": id, "output": [
        "device": "\(Device.defaultDevice())", "n": n, "iterations": iterations,
        "checksum": Double(checksum), "heldElements": Double(heldSum),
        "seconds": Date().timeIntervalSince(start),
    ]])
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let op = msg["op"] as? String else {
        FileHandle.standardError.write("worker: bad line: \(line)\n".data(using: .utf8)!); continue
    }
    switch op {
    case "cancel": if let t = msg["target"] as? String { cancels.cancel(t) }
    case "shutdown": work.sync {}; exit(0)
    case "demo.matmul":
        let id = msg["id"] as? String ?? UUID().uuidString
        let params = msg["params"] as? [String: Any] ?? [:]
        work.async { runMatmul(id: id, params: params) }
    default:
        emit(["type": "error", "id": msg["id"] as? String ?? "", "code": "unsupported_operation", "message": op])
    }
}
work.sync {}
