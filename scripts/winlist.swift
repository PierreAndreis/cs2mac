import Foundation
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let onscreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
    if (b["Width"] ?? 0) > 50 && (b["Height"] ?? 0) > 50 && layer == 0 { print("owner=\(owner) name=\(name) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0)) on=\(onscreen)") }
}
