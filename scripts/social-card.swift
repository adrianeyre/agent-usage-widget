// Draws the website's link-preview card (Open Graph and X/Twitter): 1200 × 630, dark,
// with the real dark widgets screenshot from docs/images/. Run by
// scripts/social-images.sh; it draws off-screen with AppKit, so it needs no window
// server or browser.
//
//     swift scripts/social-card.swift <repo root> <output png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: social-card.swift <repo root> <output png>\n".data(using: .utf8)!)
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2])

let width = 1200, height = 630
let size = NSSize(width: width, height: height)

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// The site's dark tokens (site/styles.css).
let background = colour(0x0b1120)
let text = colour(0xf1f5f9)
let muted = colour(0xa3b1c6)
let accent = colour(0x4ade80)
let surface = colour(0x131c2f)
let border = colour(0x1f2a40)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = size
NSGraphicsContext.current = context
let cg = context.cgContext

// Flipped, so y runs down the card as in a layout.
cg.translateBy(x: 0, y: CGFloat(height))
cg.scaleBy(x: 1, y: -1)
let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
NSGraphicsContext.current = flipped

// Background, with a soft green glow behind the screenshot and an indigo one low left.
background.setFill()
NSRect(origin: .zero, size: size).fill()
func glow(_ centre: CGPoint, _ radius: CGFloat, _ tint: NSColor) {
    let gradient = NSGradient(starting: tint, ending: tint.withAlphaComponent(0))!
    gradient.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius, options: [])
}
glow(CGPoint(x: 1000, y: 120), 620, colour(0x22c55e, 0.16))
glow(CGPoint(x: 120, y: 700), 560, colour(0x6366f1, 0.18))

// The widgets screenshot, bleeding off the right edge.
if let shot = NSImage(contentsOf: root.appendingPathComponent("docs/images/widgets-dark.png")) {
    let shotWidth: CGFloat = 700
    let shotHeight = shotWidth * shot.size.height / shot.size.width
    let frame = NSRect(x: 640, y: (CGFloat(height) - shotHeight) / 2, width: shotWidth, height: shotHeight)
    let clip = NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -30)
    shadow.set()
    background.setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    border.setStroke()
    clip.lineWidth = 2
    clip.stroke()
}

// The copy column.
let left: CGFloat = 72
let column: CGFloat = 520

if let mark = NSImage(contentsOf: root.appendingPathComponent("site/favicon.svg")) {
    mark.draw(in: NSRect(x: left, y: 64, width: 56, height: 56), from: .zero, operation: .sourceOver,
              fraction: 1, respectFlipped: true, hints: nil)
}
NSAttributedString(string: "Agent Usage", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: text,
]).draw(at: CGPoint(x: left + 72, y: 72))

let headlineStyle = NSMutableParagraphStyle()
headlineStyle.lineHeightMultiple = 0.95
let headline = NSMutableAttributedString(string: "Know if you'll run out ", attributes: [
    .font: NSFont.systemFont(ofSize: 60, weight: .heavy), .foregroundColor: text,
    .kern: -1.6, .paragraphStyle: headlineStyle,
])
headline.append(NSAttributedString(string: "before the reset.", attributes: [
    .font: NSFont.systemFont(ofSize: 60, weight: .heavy), .foregroundColor: accent,
    .kern: -1.6, .paragraphStyle: headlineStyle,
]))
headline.draw(with: NSRect(x: left, y: 168, width: column, height: 220), options: [.usesLineFragmentOrigin])

let leadStyle = NSMutableParagraphStyle()
leadStyle.lineSpacing = 6
NSAttributedString(
    string: "Claude, Codex and Copilot usage limits in your Mac's menu bar and desktop widgets, with a pace marker.",
    attributes: [.font: NSFont.systemFont(ofSize: 25, weight: .regular), .foregroundColor: muted, .paragraphStyle: leadStyle]
).draw(with: NSRect(x: left, y: 388, width: column - 20, height: 120), options: [.usesLineFragmentOrigin])

// Two chips along the bottom.
var x = left
for label in ["macOS 26 and later", "Free to install"] {
    let string = NSAttributedString(string: label, attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: text,
    ])
    let chip = NSRect(x: x, y: 522, width: string.size().width + 32, height: 44)
    let path = NSBezierPath(roundedRect: chip, xRadius: 22, yRadius: 22)
    surface.setFill()
    path.fill()
    border.setStroke()
    path.lineWidth = 1.5
    path.stroke()
    string.draw(at: CGPoint(x: chip.minX + 16, y: chip.midY - string.size().height / 2))
    x = chip.maxX + 10
}

NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
print("wrote \(output.path) (\(width)×\(height))")
