// Кадры видео симулятора → серые байты области (29.2в). Запуск: frames <video.mp4> <out.bin> <x> <y> <w> <h>
// (область в пунктах экрана 440 × 956; усреднение коробкой 3×3 на 3× — один пункт на байт).
// Файл: строка JSON `{"w":..,"h":..,"n":..}\n`, далее на кадр Double (секунды от первого кадра) + w·h байт.
import AVFoundation
import CoreVideo

let a = CommandLine.arguments
guard a.count == 7, let x0 = Int(a[3]), let y0 = Int(a[4]), let w = Int(a[5]), let h = Int(a[6]) else {
    FileHandle.standardError.write(Data("usage: frames <video> <out> <x> <y> <w> <h>\n".utf8)); exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
guard let track = asset.tracks(withMediaType: .video).first,
      let reader = try? AVAssetReader(asset: asset) else { print("нет видеодорожки"); exit(1) }
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out)
reader.startReading()
var body = Data()
var n = 0
var t0: Double?
var k = 1   // пикселей на пункт
while let sb = out.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let vw = CVPixelBufferGetWidth(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
    k = max(1, Int((Double(vw) / 440).rounded()))
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
    if t0 == nil { t0 = t }
    var ts = t - t0!
    body.append(Data(bytes: &ts, count: 8))
    var row = [UInt8](repeating: 0, count: w)
    for yy in 0..<h {
        for xx in 0..<w {
            var s = 0
            for dy in 0..<k { for dx in 0..<k {
                let p = (( y0 + yy) * k + dy) * bpr + ((x0 + xx) * k + dx) * 4
                s += Int(base[p]) + Int(base[p + 1]) * 2 + Int(base[p + 2])   // B + 2G + R
            } }
            row[xx] = UInt8(s / (4 * k * k))
        }
        body.append(contentsOf: row)
    }
    n += 1
}
let head = "{\"w\":\(w),\"h\":\(h),\"n\":\(n),\"k\":\(k)}\n"
var all = Data(head.utf8); all.append(body)
try! all.write(to: URL(fileURLWithPath: a[2]))
print("frames=\(n) k=\(k)")
