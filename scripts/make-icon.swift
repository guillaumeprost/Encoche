#!/usr/bin/env swift
// Dessine l'icône d'Encoche (aluminium argent, encoche noire) et remplit
// Notch/Assets.xcassets/AppIcon.appiconset avec toutes les tailles macOS.
//
//   swift scripts/make-icon.swift

import AppKit

let canvas: CGFloat = 1024
// Grille des icônes macOS : un carré arrondi de 824 px centré, avec de la marge pour l'ombre.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { color($0.0) } as CFArray,
        locations: stops.map(\.1)
    )!
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = ns.cgContext
    let scale = CGFloat(size) / canvas
    // Repère « écran » : origine en haut à gauche, y vers le bas.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)

    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Ombre douce sous l'icône.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xD4D6DA))
    ctx.fillPath()
    ctx.restoreGState()

    // Aluminium : clair en haut à gauche, plus sombre en bas à droite.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0xF4F5F7, 0), (0xD4D6DA, 0.55), (0xA8ABB1, 1)]),
        start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: []
    )

    // Encoche qui descend du bord haut, avec ses deux évasements.
    let u = body.width / 160 // unité de la maquette (icône de 160)
    let x0 = body.minX, y0 = body.minY
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * u, y: y0 + y * u) }
    let notch = CGMutablePath()
    // Évasements dans la partie plate du bord haut (le coin arrondi commence à 36).
    notch.move(to: p(38, -1))
    notch.addLine(to: p(122, -1))
    notch.addQuadCurve(to: p(111, 11), control: p(111, 0))
    notch.addLine(to: p(111, 26))
    notch.addQuadCurve(to: p(95, 42), control: p(111, 42))
    notch.addLine(to: p(65, 42))
    notch.addQuadCurve(to: p(49, 26), control: p(49, 42))
    notch.addLine(to: p(49, 11))
    notch.addQuadCurve(to: p(38, -1), control: p(49, 0))
    notch.closeSubpath()

    ctx.addPath(notch)
    ctx.clip()
    let notchBox = notch.boundingBox
    // Dégradé inversé : noir en haut à gauche, graphite en bas à droite.
    ctx.drawLinearGradient(
        gradient([(0x000000, 0), (0x1A1B1E, 0.6), (0x3A3B3F, 1)]),
        start: CGPoint(x: notchBox.minX, y: notchBox.minY), end: CGPoint(x: notchBox.maxX, y: notchBox.maxY), options: []
    )
    ctx.restoreGState()

    // Liseré : reflet clair à l'intérieur, contour gris pour les fonds clairs.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: cornerRadius - 2, cornerHeight: cornerRadius - 2, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.7))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0x8E9198, 0.45))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    ns.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Notch/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
        try render(size: points * factor).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(factor)x", "filename": name])
    }
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], to: iconSet.appendingPathComponent("Contents.json"))
try writeJSON(["info": ["author": "xcode", "version": 1]], to: catalog.appendingPathComponent("Contents.json"))
print("Icône générée dans \(iconSet.path)")
