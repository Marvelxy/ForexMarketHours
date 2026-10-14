// Generates the ForexMarketHours icon set: dark rounded square + clock face
// with one colored arc per trading session (UTC hours) + clock hands.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import CoreGraphics
import ImageIO
import Foundation

struct Sess { let open: Double; let close: Double; let r, g, b: Double }
let sessions = [
    Sess(open: 21, close: 6,  r: 0.13, g: 0.83, b: 0.93), // Sydney cyan
    Sess(open: 0,  close: 9,  r: 0.98, g: 0.75, b: 0.23), // Tokyo amber
    Sess(open: 6,  close: 15, r: 0.70, g: 0.45, b: 0.95), // Frankfurt purple
    Sess(open: 7,  close: 16, r: 0.38, g: 0.65, b: 1.00), // London blue
    Sess(open: 12, close: 21, r: 0.20, g: 0.83, b: 0.60), // New York green
]

func render(size: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let S = CGFloat(size)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // --- background: dark navy rounded square with vertical gradient
    let radius = S * 0.225
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg); ctx.clip()
    let top = CGColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1)
    let bottom = CGColor(red: 0.03, green: 0.05, blue: 0.11, alpha: 1)
    if let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    }
    // subtle blue glow, top-right
    let glowC = CGColor(red: 0.25, green: 0.45, blue: 1.0, alpha: 0.35)
    let clear = CGColor(red: 0.25, green: 0.45, blue: 1.0, alpha: 0)
    if let glow = CGGradient(colorsSpace: cs, colors: [glowC, clear] as CFArray, locations: [0, 1]) {
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.78, y: S * 0.82), startRadius: 0,
                               endCenter: CGPoint(x: S * 0.78, y: S * 0.82), endRadius: S * 0.55, options: [])
    }

    let cx = S / 2, cy = S / 2
    let R = S * 0.30
    let ringW = max(1.5, S * 0.028)
    let arcW = max(2.0, S * 0.085)
    let rArc = R - ringW - arcW / 2 - S * 0.008

    // --- clock face
    ctx.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))

    // --- session arcs (UTC hour -> angle, 0h at top, clockwise)
    ctx.setLineCap(.round)
    for s in sessions {
        let len = s.close > s.open ? s.close - s.open : 24 - s.open + s.close
        let steps = 72
        ctx.beginPath()
        for i in 0...steps {
            let h = s.open + len * Double(i) / Double(steps)
            let a = h / 24 * 2 * Double.pi
            let px = cx + rArc * CGFloat(sin(a))
            let py = cy + rArc * CGFloat(cos(a))
            if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) } else { ctx.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.setStrokeColor(CGColor(red: s.r, green: s.g, blue: s.b, alpha: 1))
        ctx.setLineWidth(arcW)
        ctx.strokePath()
    }

    // --- ring
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
    ctx.setLineWidth(ringW)
    ctx.strokeEllipse(in: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))

    // --- hour dots at 0/6/12/18 UTC
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
    for h in [0.0, 6, 12, 18] {
        let a = h / 24 * 2 * Double.pi
        let d = max(1.5, S * 0.014)
        let px = cx + (rArc - arcW) * CGFloat(sin(a))
        let py = cy + (rArc - arcW) * CGFloat(cos(a))
        ctx.fillEllipse(in: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d))
    }

    // --- hands: hour -> 13h (London x NY peak), minute -> top
    func hand(angleH: Double, length: CGFloat, width: CGFloat) {
        let a = angleH / 24 * 2 * Double.pi
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx, y: cy))
        ctx.addLine(to: CGPoint(x: cx + length * CGFloat(sin(a)), y: cy + length * CGFloat(cos(a))))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(width)
        ctx.strokePath()
    }
    hand(angleH: 13, length: R * 0.52, width: max(2, S * 0.035))
    hand(angleH: 0, length: R * 0.74, width: max(1.5, S * 0.024))

    // --- glowing center dot
    ctx.setShadow(offset: .zero, blur: S * 0.02, color: CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.9))
    ctx.setFillColor(CGColor(red: 0.4, green: 0.95, blue: 1.0, alpha: 1))
    let cd = max(3, S * 0.045)
    ctx.fillEllipse(in: CGRect(x: cx - cd / 2, y: cy - cd / 2, width: cd, height: cd))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    return ctx.makeImage()
}

let dir = CommandLine.arguments.dropFirst().first ?? "."
let specs: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
var failed = false
for (px, name) in specs {
    guard let img = render(size: px) else { print("render failed @\(px)"); failed = true; continue }
    let url = URL(fileURLWithPath: dir + "/" + name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("dest failed \(name)"); failed = true; continue
    }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) { print("write failed \(name)"); failed = true }
}
print(failed ? "ICON GEN FAILED" : "ICON GEN OK")
