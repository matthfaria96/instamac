// icongrid.swift <entrada.png> [saida.png]  -- mede um ícone contra a grade de
// ícones do macOS e, com saída, grava uma versão normalizada.
//
// A grade (macOS 11+): num canvas de 1024 px o CORPO do ícone é um squircle de
// 824x824 centrado -- 100 px de margem de cada lado, onde vive a sombra. O Dock,
// o Finder e o Cmd-Tab desenham todo ícone nesse canvas, então um corpo maior
// que isso aparece maior que os vizinhos e um menor, encolhido.
//
// Medida: a caixa dos pixels com alfa > 50% (o corpo, sem a sombra).
//   - corpo a 80,47% do canvas (+-1,5%) e centrado (+-1,5%): está na grade;
//   - sangrado (corpo >= 99% do canvas): recebe a máscara squircle e a margem;
//   - qualquer outra margem: é reescalado e centrado para o corpo dar 824/1024.
//
// Saída padrão: uma linha `corpo WxH em X,Y de CANVAS (PCT%) -> veredito`.
// Código de saída: 0 na grade (ou normalizado com sucesso), 1 fora dela sem
// saída pedida, 2 erro.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 2, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("uso: icongrid <entrada.png> [saida.png]\n".data(using: .utf8)!)
    exit(2)
}

let w = cg.width, h = cg.height
let space = CGColorSpaceCreateDeviceRGB()
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var x0 = w, y0 = h, x1 = -1, y1 = -1
for y in 0..<h {
    for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 127 {
        if x < x0 { x0 = x }; if x > x1 { x1 = x }
        if y < y0 { y0 = y }; if y > y1 { y1 = y }
    }
}
guard x1 >= x0, y1 >= y0 else {
    FileHandle.standardError.write("erro: imagem sem pixels opacos\n".data(using: .utf8)!)
    exit(2)
}

let canvas = Double(max(w, h))
let bodyW = Double(x1 - x0 + 1), bodyH = Double(y1 - y0 + 1)
let body = max(bodyW, bodyH)
let ratio = body / canvas
let grid = 824.0 / 1024.0
let centerOff = max(abs(Double(x0 + x1 + 1) / 2 - Double(w) / 2),
                    abs(Double(y0 + y1 + 1) / 2 - Double(h) / 2)) / canvas
let onGrid = abs(ratio - grid) <= 0.015 && centerOff <= 0.015 && w == h
let fullBleed = ratio >= 0.99

let verdict = onGrid ? "na grade da Apple (824/1024)"
    : fullBleed ? "sangrado: precisa de máscara e margem"
    : "fora da grade: corpo deveria ser \(Int((canvas * grid).rounded())) px"
print("corpo \(Int(bodyW))x\(Int(bodyH)) em \(x0),\(y0) de \(w)x\(h) (" +
      String(format: "%.1f", ratio * 100) + "%) -> \(verdict)")

guard args.count >= 3 else { exit(onGrid ? 0 : 1) }

// Normaliza para um canvas de 1024 com o corpo em 824, centrado.
let side = 1024
let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .high
if onGrid {
    out.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
} else if fullBleed {
    // Squircle de 824 px: superelipse n=5, a forma contínua dos ícones do macOS.
    let a = 412.0, n = 5.0, c = Double(side) / 2
    let path = CGMutablePath()
    for i in 0..<720 {
        let t = 2 * Double.pi * Double(i) / 720
        let ct = cos(t), st = sin(t)
        let p = CGPoint(x: c + copysign(pow(abs(ct), 2 / n), ct) * a,
                        y: c + copysign(pow(abs(st), 2 / n), st) * a)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    out.addPath(path)
    out.clip()
    out.draw(cg, in: CGRect(x: 100, y: 100, width: 824, height: 824))
} else {
    // Margem arbitrária: leva o corpo para 824 e centraliza (a sombra acompanha).
    let scale = 824.0 / body
    let cx = Double(x0 + x1 + 1) / 2, cy = Double(h) - Double(y0 + y1 + 1) / 2   // origem embaixo
    let dw = Double(w) * scale, dh = Double(h) * scale
    out.draw(cg, in: CGRect(x: 512 - cx * scale, y: 512 - cy * scale, width: dw, height: dh))
}
guard let result = out.makeImage() else { exit(2) }
let rep = NSBitmapImageRep(cgImage: result)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
do { try png.write(to: URL(fileURLWithPath: args[2])) } catch { exit(2) }
exit(0)
