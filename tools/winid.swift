// winid — lista as janelas do WindowServer com dono, id, nome e bounds.
// Ferramenta de diagnóstico local: a única forma de capturar a janela do
// Instamac (screencapture -l) sem pedir permissão de Acessibilidade.
//
//   swiftc -O -o build/winid tools/winid.swift && build/winid [filtro]
import CoreGraphics
import Foundation

let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : ""
let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let list = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []

for w in list {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    let name = (w[kCGWindowName as String] as? String) ?? ""
    let num = (w[kCGWindowNumber as String] as? Int) ?? 0
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    let b = (w[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    let x = (b["X"] as? Double) ?? 0, y = (b["Y"] as? Double) ?? 0
    let width = (b["Width"] as? Double) ?? 0, height = (b["Height"] as? Double) ?? 0
    if layer != 0 { continue }
    if !filter.isEmpty,
       !owner.lowercased().contains(filter), !name.lowercased().contains(filter) { continue }
    print("\(num)\t\(owner)\t\(name)\t\(Int(x)),\(Int(y))\t\(Int(width))x\(Int(height))")
}
