// Prints the window ID of a Dictate window: by title ("Dictate Settings") or by width (480 = the overlay).
import CoreGraphics
import Foundation

let match = CommandLine.arguments.dropFirst().first ?? "480"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String) == "Dictate" {
    let title = w[kCGWindowName as String] as? String ?? ""
    let width = ((w[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double).map { String(Int($0)) } ?? ""
    if title == match || width == match { print(w[kCGWindowNumber as String] as? Int ?? 0) }
}
