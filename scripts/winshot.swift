// List / capture on-screen windows of Wine processes only. Usage: winshot [out.png]
import Foundation
import CoreGraphics
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: Int, area: Double, name: String)? = nil
var bestBounds: [String: Double]? = nil
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.lowercased().contains("wine") || owner == "Steam" || owner.lowercased().contains("cs2") else { continue }
    let filter = ProcessInfo.processInfo.environment["WINSHOT_NAME"] ?? ""
    let wname = w[kCGWindowName as String] as? String ?? ""
    if !filter.isEmpty && !wname.lowercased().contains(filter.lowercased()) { continue }
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? ""
    print("win \(id) owner=\(owner) name=\(name) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))")
    if area > (best?.area ?? 0) { best = (id, area, name); bestBounds = b }
}
if CommandLine.arguments.count > 1, let b = best {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    var args = ["-x", "-o", "-l", String(b.id), CommandLine.arguments[1]]
    if CommandLine.arguments.count > 2, let bb = bestBounds {
        args = ["-x", "-R", "\(Int(bb["X"] ?? 0)),\(Int(bb["Y"] ?? 0)),\(Int(bb["Width"] ?? 0)),\(Int(bb["Height"] ?? 0))", CommandLine.arguments[1]]
    }
    p.arguments = args
    try p.run(); p.waitUntilExit(); print("captured window \(b.id) '\(b.name)' -> \(CommandLine.arguments[1])")
}
