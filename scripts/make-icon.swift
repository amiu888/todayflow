import AppKit
import CoreGraphics

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(h, radix: 16) ?? 0
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])!
}

let inset: CGFloat = 104
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let radius: CGFloat = 188
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Base gradient plus the icon's drop shadow in one clipped draw.
let base = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color("#273463"), color("#111A3A"), color("#070B18")] as CFArray,
    locations: [0, 0.52, 1]
)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 52, color: color("#000000", 0.55))
ctx.addPath(squircle)
ctx.clip()
ctx.drawLinearGradient(
    base,
    start: CGPoint(x: 300, y: 900),
    end: CGPoint(x: 760, y: 120),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Aurora glows.
func glow(center: CGPoint, radius r: CGFloat, hex: String, alpha: CGFloat) {
    let g = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(hex, alpha), color(hex, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
}
glow(center: CGPoint(x: 755, y: 735), radius: 430, hex: "#7C6BFF", alpha: 0.55)
glow(center: CGPoint(x: 250, y: 300), radius: 380, hex: "#22D3EE", alpha: 0.28)
glow(center: CGPoint(x: 830, y: 250), radius: 320, hex: "#F472B6", alpha: 0.16)

// Faint flowing contours behind the mark.
ctx.setLineCap(.round)
for (index, offset) in [0.0, 26.0, 52.0].enumerated() {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 150, y: 330 - offset))
    path.addCurve(
        to: CGPoint(x: 870, y: 250 - offset * 0.4),
        control1: CGPoint(x: 330, y: 430 - offset),
        control2: CGPoint(x: 610, y: 130 - offset)
    )
    ctx.addPath(path)
    ctx.setStrokeColor(color("#FFFFFF", index == 0 ? 0.10 : 0.055))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

// A soft halo behind the check.
let check = CGMutablePath()
check.move(to: CGPoint(x: 300, y: 640))
check.addCurve(
    to: CGPoint(x: 452, y: 438),
    control1: CGPoint(x: 352, y: 585),
    control2: CGPoint(x: 400, y: 492)
)
check.addCurve(
    to: CGPoint(x: 752, y: 716),
    control1: CGPoint(x: 520, y: 402),
    control2: CGPoint(x: 628, y: 612)
)

let glowStroke = check.copy(strokingWithWidth: 88, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: color("#5EA8FF", 0.6))
ctx.addPath(glowStroke)
ctx.setFillColor(color("#5EA8FF", 0.45))
ctx.fillPath()
ctx.restoreGState()

// Main check gradient.
let stroke = check.copy(strokingWithWidth: 82, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.addPath(stroke)
ctx.clip()
let checkGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color("#67E8F9"), color("#60A5FA"), color("#818CF8"), color("#B39CFF")] as CFArray,
    locations: [0, 0.36, 0.7, 1]
)!
ctx.drawLinearGradient(
    checkGradient,
    start: CGPoint(x: 290, y: 650),
    end: CGPoint(x: 770, y: 500),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

// A crisp inner highlight along the top of the ribbon.
ctx.saveGState()
ctx.addPath(stroke)
ctx.clip()
ctx.setBlendMode(.softLight)
ctx.addPath(check.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.setFillColor(color("#FFFFFF", 0.42))
ctx.fillPath()
ctx.restoreGState()

// Rim light.
ctx.addPath(squircle)
ctx.setStrokeColor(color("#FFFFFF", 0.16))
ctx.setLineWidth(3)
ctx.strokePath()

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon-1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
