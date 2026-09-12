// OCR the CS2 `cl_showfps 2` overlay from a window capture. Usage: fpsread <png> [debug.png]
// The overlay is drawn in red; we isolate red pixels (black on white) so Vision reads it cleanly,
// then print "now=<fps> f60=<fps> f240=<fps> f1000=<fps> min=<ms> max=<ms>". Exit 1 if unreadable.
import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers
let path = CommandLine.arguments[1]
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(path)"); exit(2) }
let scale = 2
let w = img.width * scale, h = img.height * 40 / 100 * scale
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(img, in: CGRect(x: 0, y: h - img.height * scale, width: img.width * scale, height: img.height * scale))
let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
for i in stride(from: 0, to: w * h * 4, by: 4) {
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    let red = r > 140 && g < 110 && b < 110 && r - max(g, b) > 60
    let v: UInt8 = red ? 0 : 255
    px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
}
let bw = ctx.makeImage()!
if CommandLine.arguments.count > 2 {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, bw, nil); CGImageDestinationFinalize(dst)
}
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: bw, options: [:]).perform([req])
var frags: [(y: CGFloat, x: CGFloat, t: String)] = []
for obs in req.results ?? [] {
    if let t = obs.topCandidates(1).first?.string { frags.append((obs.boundingBox.midY, obs.boundingBox.minX, t)) }
}
frags.sort { abs($0.y - $1.y) > 0.015 ? $0.y > $1.y : $0.x < $1.x }
var lines: [String] = []
var lastY: CGFloat = -1
for f in frags {
    if lastY >= 0 && abs(f.y - lastY) <= 0.015 { lines[lines.count - 1] += " " + f.t } else { lines.append(f.t); lastY = f.y }
}
let all = "\n" + lines.joined(separator: "\n").replacingOccurrences(of: " ", with: "")
func num(_ s: String, _ pattern: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}
var out: [String] = []
if let v = num(all, "(\\d+)fps\\(") { out.append("now=\(v)") }
if let v = num(all, "\\n60[A-Za-z=]*:(\\d+\\.\\d)") { out.append("f60=\(v)") }
if let v = num(all, "\\n240[A-Za-z=]*:(\\d+\\.\\d)") { out.append("f240=\(v)") }
if let v = num(all, "\\n1000[A-Za-z=]*:(\\d+\\.\\d)") { out.append("f1000=\(v)") }
if let v = num(all, "\\n1000[A-Za-z=]*:[^|I]*[|I]min:(\\d+\\.\\d+)ms") { out.append("min=\(v)") }
if let v = num(all, "\\n1000[A-Za-z=]*:[^|I]*[|I]min:[^,]*,max:(\\d+\\.\\d+)ms") { out.append("max=\(v)") }
if ProcessInfo.processInfo.environment["FPSREAD_DEBUG"] != nil { for l in lines { FileHandle.standardError.write((l + "\n").data(using: .utf8)!) } }
print(out.joined(separator: " "))
exit(out.isEmpty ? 1 : 0)
