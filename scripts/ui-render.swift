// Headless renders of GW2 on Mac's windows, for reviews and the comparison with the approved
// design (its exports, when given). Compiled with the app's sources (-D GW2_RENDER, which drops the
// app's own entry point) by scripts/ui-render.sh. No window is ever shown: each view is hosted
// in an NSHostingView inside a borderless window that is never ordered on screen, and drawn with
// cacheDisplay at 2x into a PNG. The app never activates (activation policy .prohibited). The
// installer state is made up here; nothing runs gw2om.sh (GW2OM_RENDER=1 keeps Settings from
// reloading).
//
//   ui-render <out dir> [<design exports dir>]   PNGs of every state, light and dark; with the
//                                                exports, compare-*.png: the design | the render

import AppKit
import SwiftUI

@main
struct UIRender {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let args = Array(CommandLine.arguments.dropFirst())
    guard let out = args.first else {
      print("usage: ui-render <out dir> [<design exports dir>]")
      exit(2)
    }
    MainActor.assumeIsolated {
      Brand.registerFonts()
      Task { @MainActor in
        await renderAll(URL(fileURLWithPath: out), exports: args.count > 1 ? URL(fileURLWithPath: args[1]) : nil)
        exit(0)
      }
    }
    app.run()
  }
}

// MARK: - Drawing

@MainActor
func render<V: View>(_ view: V, size: CGSize, dark: Bool, chrome: Bool = true) async -> NSBitmapImageRep {
  let host = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
  let win = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless],
                     backing: .buffered, defer: true)
  win.isReleasedWhenClosed = false
  win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  win.contentView = host
  host.frame = CGRect(origin: .zero, size: size)
  // let SwiftUI lay out, load the art and settle its animations
  for _ in 0..<12 {
    host.layoutSubtreeIfNeeded()
    try? await Task.sleep(for: .milliseconds(100))
  }
  let scale: CGFloat = 2
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = size
  host.cacheDisplay(in: host.bounds, to: rep)
  win.close()
  return chrome ? windowChrome(rep, size: size, dark: dark) : rep
}

// The window's frame as the design draws it: rounded corners (12), a hairline and the traffic
// lights (the real window gets the system's own)
@MainActor
func windowChrome(_ content: NSBitmapImageRep, size: CGSize, dark: Bool) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: content.pixelsWide, pixelsHigh: content.pixelsHigh,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = size
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let shape = NSBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
  NSGraphicsContext.saveGraphicsState()
  shape.addClip()
  content.draw(in: CGRect(origin: .zero, size: size))
  NSGraphicsContext.restoreGraphicsState()
  NSColor(white: 0, alpha: 0x26 / 255).setStroke()
  shape.lineWidth = 1
  shape.stroke()
  for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    let dot = NSBezierPath(ovalIn: CGRect(x: 16 + CGFloat(i) * 20, y: size.height - 16 - 12, width: 12, height: 12))
    NSColor(hex: UInt32(hex)).setFill()
    dot.fill()
    NSColor(white: 0, alpha: 0x1F / 255).setStroke()
    dot.lineWidth = 0.5
    dot.stroke()
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print("wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// The design's export and the render side by side, the same height, with labels
func compare(design: URL, render: NSBitmapImageRep, to url: URL) {
  guard let d = NSBitmapImageRep(data: (try? Data(contentsOf: design)) ?? Data()) else { return }
  let h = max(d.pixelsHigh, render.pixelsHigh), gap = 40, label = 60
  let w = d.pixelsWide + gap + render.pixelsWide
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h + label, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor(white: 0.5, alpha: 1).setFill()
  CGRect(x: 0, y: 0, width: w, height: h + label).fill()
  d.draw(in: CGRect(x: 0, y: h - d.pixelsHigh, width: d.pixelsWide, height: d.pixelsHigh))
  render.draw(in: CGRect(x: d.pixelsWide + gap, y: h - render.pixelsHigh, width: render.pixelsWide, height: render.pixelsHigh))
  let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.white]
  ("Design: \(design.lastPathComponent)" as NSString).draw(at: CGPoint(x: 10, y: h + 12), withAttributes: font)
  ("Render" as NSString).draw(at: CGPoint(x: d.pixelsWide + gap + 10, y: h + 12), withAttributes: font)
  NSGraphicsContext.restoreGraphicsState()
  write(rep, url)
}

// MARK: - States

@MainActor
func installer(_ state: String) -> Installer {
  let i = Installer()
  var st: [String: String] = [
    "version": "0.1.0", "engine": "cx-26.3.0-8", "engine_title": "CrossOver 26.3 · Wine 11", "rosetta": "yes",
    "arch": "arm64", "installed": "yes", "installed_version": "0.1.0", "engine_installed": "yes", "graphics": "yes",
    "gamemode": "yes", "route": "steam", "steam": "yes", "game": "yes", "stage": "finished",
    "disk_free": "412000000000", "disk_needed": "75000000000", "busy": "none", "uiscale": "off",
  ]
  i.route = .steam
  switch state {
  case "choose":
    // as the design: the engine and the bottle are there (an earlier run), the game is not, the
    // disk is short
    st["game"] = "no"; st["stage"] = "none"; st["steam"] = "no"; st["route"] = ""
    st["disk_free"] = "62000000000"
  case "fresh":
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "gamemode": "no", "game": "no",
                     "stage": "none", "steam": "no", "route": "", "installed_version": ""]) { $1 }
  case "arenanet":
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "gamemode": "no", "game": "no",
                     "stage": "none", "steam": "no", "route": ""]) { $1 }
    i.route = .arenanet
    i.setupFile = URL(fileURLWithPath: "/Users/you/Downloads/Gw2Setup-64.exe")
    i.setupCheck = .ok("Gw2Setup-64.exe · signed by ArenaNet, LLC")
  case "installing":
    st["game"] = "no"; st["stage"] = "none"; st["route"] = ""
    i.operation = .install
    i.phase = .working(.install)
    i.stepIndex = 2
    i.progress = .init(label: "SteamSetup.exe", done: 2_100_000, total: 3_400_000)
  case "waiting":
    st["game"] = "no"; st["stage"] = "waiting_game"
    i.operation = .install
    i.phase = .waitingForGame
    i.stepIndex = 3
    i.progress = .init(label: "Guild Wars 2", done: 21_400_000_000, total: 58_900_000_000)
  case "failed":
    st["game"] = "no"; st["stage"] = "none"; st["route"] = ""; st["installed"] = "no"; st["engine_installed"] = "no"
    st["graphics"] = "no"; st["gamemode"] = "no"
    i.phase = .failed(.install, "The download of the Wine engine failed (curl status 6). Check your internet connection and try again.")
  case "uninstalling":
    i.operation = .uninstall
    i.phase = .working(.uninstall)
    i.stepIndex = 1
  default: break
  }
  i.status = st
  return i
}

@MainActor
func settings() -> GameSettings {
  let s = GameSettings()
  s.preview(["installed": "yes", "running": "no", "retina": "on", "fpscap": "off", "metalfx": "off", "hud": "off",
             "warm": "on", "coolworkers": "3", "fastlocks": "on", "ncpu": "8", "uiscale": "off", "uiscale_state": "off",
             "uiscale_size": "1.75", "uiscale_sans": "on", "uiscale_cinema": "on", "gamemode": "on", "launchopts": "",
             "route": "steam", "updates": "off", "debug": "off"])
  return s
}

@MainActor
func renderAll(_ dir: URL, exports: URL?) async {
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let size = MainView.designSize
  let mains: [(String, String, Bool, String?)] = [
    ("main-choose-light", "choose", false, "1-choose-install.png"),
    ("main-installing-light", "installing", false, "2-installing.png"),
    ("main-ready-light", "ready", false, "3-ready-to-play.png"),
    ("main-ready-dark", "ready", true, "5-ready-to-play-dark.png"),
    ("main-choose-dark", "choose", true, nil),
    ("main-installing-dark", "installing", true, nil),
    ("main-fresh-light", "fresh", false, nil),
    ("main-arenanet-light", "arenanet", false, nil),
    ("main-waiting-dark", "waiting", true, nil),
    ("main-waiting-light", "waiting", false, nil),
    ("main-failed-light", "failed", false, nil),
    ("main-uninstalling-light", "uninstalling", false, nil),
  ]
  for (name, state, dark, design) in mains {
    let rep = await render(MainView(installer: installer(state), settings: settings()), size: size, dark: dark)
    write(rep, dir.appendingPathComponent(name + ".png"))
    if let exports, let design { compare(design: exports.appendingPathComponent(design), render: rep,
                                         to: dir.appendingPathComponent("compare-" + name + ".png")) }
  }
  for pane in SettingsPane.allCases {
    for dark in [false, true] where !dark || pane == .performance || pane == .interface {
      UserDefaults.standard.set(pane.rawValue, forKey: SettingsView.selectedPaneKey)
      let name = "settings-\(pane.rawValue)-\(dark ? "dark" : "light")"
      let rep = await render(SettingsView(settings: settings()), size: SettingsView.designSize, dark: dark)
      write(rep, dir.appendingPathComponent(name + ".png"))
      if let exports, pane == .performance, !dark {
        compare(design: exports.appendingPathComponent("4-settings-performance.png"), render: rep,
                to: dir.appendingPathComponent("compare-" + name + ".png"))
      }
    }
  }
  for dark in [false, true] {
    let sheet = InterfaceWarning(isPresented: .constant(true)) {}
    write(await render(sheet, size: CGSize(width: 460, height: 300), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-interface-warning-\(dark ? "dark" : "light").png"))
  }
}
