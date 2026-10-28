import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A system-wide monotonic clock (mach absolute time), so the host and the worker can compare
/// timestamps across processes.
public enum Clock {
    public static func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }
}

/// `phys_footprint` of any process of ours, the number Gaea's ledger and Activity Monitor show.
public func physFootprint(pid: pid_t) -> UInt64? {
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return status == 0 ? info.ri_phys_footprint : nil
}

/// Machine-wide memory that isn't file cache: anonymous (internal) pages, wired and compressed.
/// Taken before a worker starts and after it exits, it shows whether the memory came back.
public func systemAnonymousBytes() -> UInt64? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &stats) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { return nil }
    let pages = UInt64(stats.internal_page_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
    return pages * UInt64(getpagesize())
}

/// Polls a process's phys_footprint on a background thread and keeps the peak.
public final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var running = true
    private let pid: pid_t

    public init(pid: pid_t, interval: TimeInterval = 0.02) {
        self.pid = pid
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let go = running
                lock.unlock()
                if !go { break }
                if let value = physFootprint(pid: pid) {
                    lock.lock(); peak = max(peak, value); lock.unlock()
                }
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }

    /// The peak since the last reset, then start over.
    public func takePeak() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let value = max(peak, physFootprint(pid: pid) ?? 0)
        peak = 0
        return value
    }

    public func stop() { lock.lock(); running = false; lock.unlock() }
}

// MARK: - Pixels and image files

/// Tightly packed RGBA pixels, 8 or 16 bits per component (16-bit is host byte order).
public struct Pixels: @unchecked Sendable {
    public var width: Int
    public var height: Int
    public var bitsPerComponent: Int
    public var data: Data

    public init(width: Int, height: Int, bitsPerComponent: Int, data: Data) {
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.data = data
    }

    public var bytesPerRow: Int { width * 4 * bitsPerComponent / 8 }

    static func bitmapInfo(_ bpc: Int) -> UInt32 {
        bpc == 16
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
    }

    /// Draw `image` into a new buffer: this is where a lazy decode actually happens.
    public init(drawing image: CGImage, width: Int? = nil, height: Int? = nil, bitsPerComponent: Int,
                offset: CGPoint = .zero) {
        let w = width ?? image.width, h = height ?? image.height
        let bpr = w * 4 * bitsPerComponent / 8
        var data = Data(count: bpr * h)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: bitsPerComponent,
                                    bytesPerRow: bpr, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: Pixels.bitmapInfo(bitsPerComponent))!
            context.interpolationQuality = .high
            // Cover the canvas (aspect fill), shifted by `offset` so consecutive frames differ like a pan.
            let scale = max(Double(w) / Double(image.width), Double(h) / Double(image.height)) * 1.1
            let dw = Double(image.width) * scale, dh = Double(image.height) * scale
            context.draw(image, in: CGRect(x: (Double(w) - dw) / 2 + offset.x, y: (Double(h) - dh) / 2 + offset.y,
                                           width: dw, height: dh))
        }
        self.init(width: w, height: h, bitsPerComponent: bitsPerComponent, data: data)
    }

    public func cgImage() -> CGImage {
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: bitsPerComponent,
                       bitsPerPixel: 4 * bitsPerComponent, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: Pixels.bitmapInfo(bitsPerComponent)),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// How a spooled image is stored.
public enum SpoolFormat: String, Sendable, CaseIterable {
    /// Raw RGBA8, no header: what a frame handoff would carry with no codec at all.
    case raw
    /// PNG, 8 bits per component.
    case png
    /// Uncompressed TIFF, 16 bits per component.
    case tiff16

    public var fileExtension: String { self == .raw ? "rgba" : (self == .png ? "png" : "tiff") }
    public var mediaType: String {
        switch self {
        case .raw: "application/octet-stream"
        case .png: "image/png"
        case .tiff16: "image/tiff"
        }
    }
    public var bitsPerComponent: Int { self == .tiff16 ? 16 : 8 }
}

/// Encode pixels into the file bytes of `format` (raw is the pixels themselves).
public func encode(_ pixels: Pixels, as format: SpoolFormat) -> Data {
    switch format {
    case .raw:
        return pixels.data
    case .png, .tiff16:
        let out = NSMutableData()
        let type = (format == .png ? UTType.png : UTType.tiff).identifier as CFString
        let destination = CGImageDestinationCreateWithData(out, type, 1, nil)!
        CGImageDestinationAddImage(destination, pixels.cgImage(), nil)
        precondition(CGImageDestinationFinalize(destination), "encode \(format) failed")
        return out as Data
    }
}

/// Decode file bytes back into pixels (fully: the image is drawn into a buffer).
public func decode(_ data: Data, as format: SpoolFormat, width: Int, height: Int) -> Pixels {
    switch format {
    case .raw:
        return Pixels(width: width, height: height, bitsPerComponent: 8, data: data)
    case .png, .tiff16:
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)!
        return Pixels(drawing: image, bitsPerComponent: format.bitsPerComponent)
    }
}

/// Read a whole file into memory with plain read(2) calls (no mapping), as a worker would.
public func readFile(_ url: URL) throws -> Data {
    try Data(contentsOf: url, options: [])
}

/// Write bytes with plain write(2) calls: no atomic rename, no fsync, as the host spools today.
public func writeFile(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [])
}

/// Run `body` for 0..<count, in parallel when asked.
public func forEach(_ count: Int, parallel: Bool, _ body: (Int) -> Void) {
    if parallel {
        DispatchQueue.concurrentPerform(iterations: count, execute: body)
    } else {
        for i in 0..<count { body(i) }
    }
}

/// Seconds, rounded to the microsecond, for JSON.
public func secs(_ start: Double, _ end: Double = Clock.now()) -> Double { ((end - start) * 1e6).rounded() / 1e6 }
