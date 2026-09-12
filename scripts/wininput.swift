// Post input to the largest on-screen Wine window (the game). Usage:
//   wininput focus                 bring the window's app to front
//   wininput click <hold_ms>       left mouse down/up at the window centre
//   wininput key <keycode> [ms]    press a virtual key (macOS keycodes, e.g. 35 = p)
//   wininput move <dx> <dy>        relative mouse move (posts a mouseMoved delta)
import Foundation
import AppKit
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (pid: Int32, bounds: [String: Double], area: Double)? = nil
let filter = ProcessInfo.processInfo.environment["WINSHOT_NAME"] ?? "Counter"
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.lowercased().contains("wine") || owner.lowercased().contains("cs2") else { continue }
    let wname = w[kCGWindowName as String] as? String ?? ""
    if !filter.isEmpty && !wname.lowercased().contains(filter.lowercased()) { continue }
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if area > (best?.area ?? 0) { best = (w[kCGWindowOwnerPID as String] as? Int32 ?? 0, b, area) }
}
guard let win = best else { fputs("no game window\n", stderr); exit(1) }
let cx = (win.bounds["X"] ?? 0) + (win.bounds["Width"] ?? 0) / 2
let cy = (win.bounds["Y"] ?? 0) + (win.bounds["Height"] ?? 0) / 2
let center = CGPoint(x: cx, y: cy)
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func sleepMs(_ ms: Int) { usleep(UInt32(ms) * 1000) }
let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "focus"
if let app = NSRunningApplication(processIdentifier: win.pid) { app.activate(options: [.activateIgnoringOtherApps]) }
sleepMs(150)
switch cmd {
case "focus":
    print("focused pid \(win.pid) at \(Int(cx)),\(Int(cy))")
case "click":
    let hold = args.count > 2 ? Int(args[2]) ?? 50 : 50
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left))
    sleepMs(hold)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left))
case "key":
    let code = CGKeyCode(args.count > 2 ? Int(args[2]) ?? 35 : 35)
    let hold = args.count > 3 ? Int(args[3]) ?? 60 : 60
    post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)); sleepMs(hold)
    post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false))
case "move":
    let dx = args.count > 2 ? Double(args[2]) ?? 0 : 0, dy = args.count > 3 ? Double(args[3]) ?? 0 : 0
    let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)
    e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx)); e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
    post(e)
default: fputs("unknown command\n", stderr); exit(2)
}
