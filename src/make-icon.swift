// The app icon: an Icon Composer document (app/src/AppIcon.icon) that macOS 26 and later draws as a
// Liquid Glass icon (glass rim, specular highlights, shadow; Default, Dark, Tinted and Clear).
// The design (Jan's, the .pen frame "App Icon", docs/design/exports/6-app-icon.png): the window's
// "GW2 / ON MAC" wordmark in Cinzel over a crimson ensō with ink splatter, on dark ink. Original
// artwork: no ArenaNet or Guild Wars logo. The layers carry no tile, rim or shadow: the system draws
// those, and icon.json holds the background gradient and each group's glass settings (fine-tune
// them in Xcode's Icon Composer). Structure and preview as SWTOR on Mac's src/make-icon.swift.
//
//   swift app/src/make-icon.swift layers app/src/AppIcon.icon
//       writes the wordmark layer into Assets/ (icon-ring.png is the design's own artwork,
//       docs/design/icon-ring.png; icon.json is left as it is)
//   swift app/src/make-icon.swift preview app/src/AppIcon.icon <sheet.png> [other.icns]
//       renders a review sheet with Icon Composer's ictool: the six appearances, and every size on
//       light and on dark, optionally next to another app's .icns
//
// app/build.sh compiles the document with actool into Assets.car and a fallback AppIcon.icns.
import AppKit
import CoreImage
import CoreText

let args = CommandLine.arguments
guard args.count >= 3, (args[1] == "layers" && args.count == 3) || (args[1] == "preview" && (4...5).contains(args.count)) else {
  FileHandle.standardError.write("usage: make-icon.swift layers <AppIcon.icon> | preview <AppIcon.icon> <sheet.png> [other.icns]\n".data(using: .utf8)!)
  exit(1)
}
let doc = URL(fileURLWithPath: args[2])

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
func f(_ x: CGFloat) -> String { String(format: "%.2f", x) }

func svg(_ body: String) -> String {
  """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\
  <g transform="matrix(1 0 0 -1 0 1024)">\(body)</g></svg>

  """
}

// --- wordmark: Cinzel Bold (the app's own copy, app/src/fonts, SIL OFL 1.1; the SVG carries the
// outlines, so only `layers` needs the font). Returns the outline and the line's ascent/descent.
func cinzel(_ s: String, size: CGFloat, spacing: CGFloat) -> (path: CGPath, width: CGFloat, ascent: CGFloat, descent: CGFloat) {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fonts/Cinzel-Variable.ttf") as CFURL
  let desc = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
  let wght = 0x77676874 as NSNumber
  let d2 = CTFontDescriptorCreateCopyWithAttributes(desc, [kCTFontVariationAttribute: [wght: 700]] as CFDictionary)
  let font = CTFontCreateWithFontDescriptor(d2, size, nil)
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: spacing]))
  let path = CGMutablePath()
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    let rf = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for i in 0..<n { if let g = CTFontCreatePathForGlyph(rf, glyphs[i], nil) { path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y)) } }
  }
  // the advance without the spacing after the last letter (as a design tool sets it)
  let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - spacing
  return (path, width, CTFontGetAscent(font), CTFontGetDescent(font))
}
func pathD(_ p: CGPath) -> String {
  var out = ""
  p.applyWithBlock { e in
    let pt = e.pointee.points
    switch e.pointee.type {
    case .moveToPoint: out += "M\(f(pt[0].x)) \(f(pt[0].y))"
    case .addLineToPoint: out += "L\(f(pt[0].x)) \(f(pt[0].y))"
    case .addQuadCurveToPoint: out += "Q\(f(pt[0].x)) \(f(pt[0].y)) \(f(pt[1].x)) \(f(pt[1].y))"
    case .addCurveToPoint: out += "C\(f(pt[0].x)) \(f(pt[0].y)) \(f(pt[1].x)) \(f(pt[1].y)) \(f(pt[2].x)) \(f(pt[2].y))"
    case .closeSubpath: out += "Z"
    @unknown default: break
    }
  }
  return out
}
// As the .pen's App Icon: "GW2" 250 px, letter spacing 6, #FFF6E8; 14 px below its line box a row:
// a gold rule 70 x 6 (radius 3) #E9C46A, 22 px, "ON MAC" 76 px, letter spacing 22, #F2D27A,
// 22 px, the rule again. The two lines' boxes, centred in the 1024 canvas.
func wordSVG() -> String {
  let top = cinzel("GW2", size: 250, spacing: 6)
  let sub = cinzel("ON MAC", size: 76, spacing: 22)
  let ruleW: CGFloat = 70, ruleH: CGFloat = 6, gap: CGFloat = 22, between: CGFloat = 14
  // "GW2" has line height 1 (its box is 250 tall, the font's ascent and descent centred in it, as
  // the header's wordmark); "ON MAC" the font's own (ascent + descent)
  let topH: CGFloat = 250, subH = sub.ascent + sub.descent
  let blockH = topH + between + subH
  // y up: the block's top at 512 + blockH / 2
  let blockTop = 512 + blockH / 2
  let topBase = blockTop - (topH - top.ascent - top.descent) / 2 - top.ascent
  let subBase = blockTop - topH - between - sub.ascent
  let rowW = ruleW + gap + sub.width + gap + ruleW
  var t1 = CGAffineTransform(translationX: 512 - top.width / 2, y: topBase)
  var t2 = CGAffineTransform(translationX: 512 - rowW / 2 + ruleW + gap, y: subBase)
  let m = top.path.copy(using: &t1)!, s = sub.path.copy(using: &t2)!
  // the rules on the middle of the capitals
  let capMid = subBase + s.boundingBoxOfPath.height / 2 + (s.boundingBoxOfPath.minY - subBase)
  let rules = [512 - rowW / 2, 512 + rowW / 2 - ruleW].map {
    "<rect x=\"\(f($0))\" y=\"\(f(capMid - ruleH / 2))\" width=\"\(f(ruleW))\" height=\"\(f(ruleH))\" rx=\"3\" fill=\"#E9C46A\"/>"
  }.joined()
  return svg("<path d=\"\(pathD(m))\" fill=\"#FFF6E8\"/>" + rules + "<path d=\"\(pathD(s))\" fill=\"#F2D27A\"/>")
}

if args[1] == "layers" {
  let assets = doc.appendingPathComponent("Assets")
  try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
  try wordSVG().write(to: assets.appendingPathComponent("wordmark.svg"), atomically: true, encoding: .utf8)
  guard FileManager.default.fileExists(atPath: assets.appendingPathComponent("icon-ring.png").path) else {
    FileHandle.standardError.write("Assets/icon-ring.png is missing: copy docs/design/icon-ring.png there\n".data(using: .utf8)!)
    exit(1)
  }
  print("layers written to \(assets.path)")
  exit(0)
}

// --- preview: Icon Composer's own renders, so the sheet shows what the system will draw
let ictool = ProcessInfo.processInfo.environment["ICTOOL"]
  ?? "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("make-icon-\(getpid())")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
// ictool draws the shape edge to edge; an app icon puts it on Apple's grid (824 of 1024 units),
// so for the size rows the shape is rendered at 824/1024 and centred, like a .icns.
func render(_ rendition: String, _ px: Int, grid: Bool) -> CGImage {
  let body = grid ? max(1, Int((Double(px) * 824 / 1024).rounded())) : px
  let out = tmp.appendingPathComponent("\(rendition)-\(px)-\(grid).png")
  let p = Process()
  p.executableURL = URL(fileURLWithPath: ictool)
  p.arguments = [doc.path, "--export-image", "--output-file", out.path, "--platform", "macOS", "--rendition", rendition,
                 "--width", "\(body)", "--height", "\(body)", "--scale", "1"]
  p.standardOutput = FileHandle.nullDevice
  try! p.run()
  p.waitUntilExit()
  guard p.terminationStatus == 0, let img = NSBitmapImageRep(data: try! Data(contentsOf: out))?.cgImage else {
    FileHandle.standardError.write("ictool failed for \(rendition) at \(px) px\n".data(using: .utf8)!)
    exit(1)
  }
  let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let o = CGFloat(px - body) / 2
  c.draw(img, in: CGRect(x: o, y: o, width: CGFloat(body), height: CGFloat(body)))
  return c.makeImage()!
}
let renditions = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]
let sizes = [1024, 256, 128, 64, 32, 16]
let shown = { (px: Int) -> CGFloat in px == 1024 ? 512 : CGFloat(px) }
var groups: [(String, light: [Int: CGImage], dark: [Int: CGImage])] = [
  (doc.lastPathComponent, Dictionary(uniqueKeysWithValues: sizes.map { ($0, render("Default", $0, grid: true)) }),
   Dictionary(uniqueKeysWithValues: sizes.map { ($0, render("Dark", $0, grid: true)) })),
]
if args.count == 5, let other = NSImage(contentsOfFile: args[4]) {
  var imgs: [Int: CGImage] = [:]
  for px in sizes {
    var rect = CGRect(x: 0, y: 0, width: px, height: px)
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    if let cg = other.cgImage(forProposedRect: &rect, context: nil, hints: nil) { c.draw(cg, in: rect) }
    imgs[px] = c.makeImage()
  }
  let app = URL(fileURLWithPath: args[4]).pathComponents.last { $0.hasSuffix(".app") }
  groups.append((app.map { String($0.dropLast(4)) } ?? URL(fileURLWithPath: args[4]).lastPathComponent, imgs, imgs))
}
let looks = renditions.map { ($0, render($0, 512, grid: false)) }

let gap: CGFloat = 36, margin: CGFloat = 48, labelH: CGFloat = 70, rowH: CGFloat = 512 + labelH + 40, lookW: CGFloat = 300
let groupW = sizes.map(shown).reduce(0, +) + gap * CGFloat(sizes.count - 1)
let W = max(margin * 2 + groupW * CGFloat(groups.count) + 90 * CGFloat(groups.count - 1),
            margin * 2 + (lookW + gap) * CGFloat(renditions.count) - gap)
let looksH = lookW + labelH + 40
let H = margin * 2 + looksH + rowH * 2
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
let c = NSGraphicsContext.current!.cgContext
c.interpolationQuality = .high
let labelFont = NSFont.systemFont(ofSize: 26, weight: .semibold)
let sizeFont = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .regular)
// the six appearances, on a mid grey (Tinted and Clear take their colour from the wallpaper)
c.setFillColor(rgb(0.45, 0.46, 0.48))
c.fill(CGRect(x: 0, y: H - margin - looksH, width: W, height: looksH + margin))
for (i, (name, img)) in looks.enumerated() {
  let x = margin + CGFloat(i) * (lookW + gap), y = H - margin - looksH + 30
  c.draw(img, in: CGRect(x: x, y: y, width: lookW, height: lookW))
  (name as NSString).draw(at: NSPoint(x: x, y: y + lookW + 10), withAttributes: [.font: labelFont, .foregroundColor: NSColor.white])
}
// every size at 1:1 (1024 at half size): Default on light, Dark on dark
for (row, dark) in [false, true].enumerated() {
  let y0 = H - margin - looksH - rowH * CGFloat(row + 1)
  c.setFillColor(dark ? rgb(0.12, 0.12, 0.13) : rgb(0.93, 0.93, 0.94))
  c.fill(CGRect(x: 0, y: row == 0 ? y0 : 0, width: W, height: row == 0 ? rowH : y0 + rowH))
  let ink = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)
  var x = margin
  for g in groups {
    (g.0 as NSString).draw(at: NSPoint(x: x, y: y0 + rowH - 44), withAttributes: [.font: labelFont, .foregroundColor: ink])
    for px in sizes {
      let d = shown(px)
      c.draw((dark ? g.dark : g.light)[px]!, in: CGRect(x: x, y: y0 + 40 + (512 - d) / 2, width: d, height: d))
      ("\(px)" as NSString).draw(at: NSPoint(x: x, y: y0 + 4), withAttributes: [.font: sizeFont, .foregroundColor: ink.withAlphaComponent(0.7)])
      x += d + gap
    }
    x += 90 - gap
  }
}
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("preview written to \(args[3])")
