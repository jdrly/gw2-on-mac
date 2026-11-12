// Headless renders of the app's windows, for reviews and the comparison with the approved
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
    "version": "0.2.0-dev.2", "engine": "mach9-v0.3.1", "engine_title": "Mach9 0.3.1 · Wine 11.21",
    "engine_dxmt": "d903db89036", "dxmt": "fork", "dxmt_tree": "fork", "dxmt_version": "v0.80-489-g2483559",
    "dxmt_release": "0.80", "dxmt_commit": "2483559", "metal": "3",
    "wine": "mine", "wine_ready": "yes", "wine_file": "mine", "wine_commit": "d831f808236c", "wine_release": "11.21",
    "wine_build": "d831f808236c",
    "macdrv": "mine", "macdrv_ready": "yes", "macdrv_file": "mine", "macdrv_commit": "d831f808236c", "macdrv_release": "11.21",
    "macdrv_build": "d831f808236c",
    "fex": "engine", "fex_ready": "yes", "fex_file": "engine", "fex_commit": "9d4fa4b46b1", "fex_build": "bff3f7c3686b",
    "macos": "27.2", "macos_min": "26.4", "macos_ok": "yes",
    "arch": "arm64", "installed": "yes", "installed_version": "0.2.0-dev.2", "engine_installed": "yes", "graphics": "yes",
    "gamemode": "engine", "route": "steam", "steam": "yes", "game": "yes", "stage": "finished",
    "disk_free": "412000000000", "disk_needed": "75000000000", "busy": "none", "uiscale": "off",
  ]
  i.route = .steam
  switch state {
  case "choose":
    // as the design: the engine and the bottle are there (an earlier run), the game is not, the
    // disk is short
    st["game"] = "no"; st["stage"] = "none"; st["steam"] = "no"; st["route"] = ""
    st["disk_free"] = "62000000000"
  case "ready-engine":
    // the engine's own ntdll.so, winemac.so and DXMT, as Settings can ask for them
    st = st.merging(["dxmt": "engine", "dxmt_tree": "engine", "wine": "engine", "wine_file": "engine",
                     "wine_commit": "53def89293a", "wine_release": "", "macdrv": "engine", "macdrv_file": "engine",
                     "macdrv_commit": "53def89293a", "macdrv_release": ""]) { $1 }
  case "ready-mixed":
    // my ntdll.so next to the engine's own winemac.so
    st = st.merging(["macdrv": "engine", "macdrv_file": "engine", "macdrv_commit": "53def89293a",
                     "macdrv_release": ""]) { $1 }
  case "ready-other":
    // another ntdll.so (an earlier build of mine) that the next Play replaces, next to my winemac.so
    st = st.merging(["wine_ready": "switch", "wine_file": "other", "wine_commit": "", "wine_release": ""]) { $1 }
  case "ready-fex":
    // my FEX in the engine (set fex mine from Terminal), next to my ntdll.so and winemac.so
    st = st.merging(["fex": "mine", "fex_file": "mine", "fex_commit": "bff3f7c3686b"]) { $1 }
  case "ready-repair":
    // an earlier version's install whose engine graphics aren't the engine's own: Repair
    st["graphics"] = "other"; st["installed_version"] = "0.2.0-dev.0"
  case "fresh-old-macos":
    // a Mac below the engine's macOS: the macOS check is red and Install says why
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "game": "no",
                     "stage": "none", "steam": "no", "route": "", "installed_version": "",
                     "macos": "26.3", "macos_ok": "no"]) { $1 }
  case "fresh":
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "game": "no",
                     "stage": "none", "steam": "no", "route": "", "installed_version": ""]) { $1 }
  case "arenanet":
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "game": "no",
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
    st["graphics"] = "no"
    i.phase = .failed(.install, "The download of the Wine engine failed (curl status 6). Check your internet connection and try again.")
  case "existing", "existing-copy", "existing-none", "importing":
    // Game files I already have: what a scan of other Wine apps found
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "game": "no",
                     "stage": "none", "steam": "no", "route": "", "installed_version": ""]) { $1 }
    i.route = .existing
    i.scanned = true
    let home = "/Users/you"
    i.gameFolders = state == "existing-none" ? [] : [
      .init(source: "CrossOver · Steam", route: .steam, bytes: 71_400_000_000, sameDisk: true, hasSettings: true,
            path: home + "/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Guild Wars 2"),
      .init(source: "Whisky · Guild Wars 2", route: .arenanet, bytes: 69_800_000_000, sameDisk: true, hasSettings: true,
            path: home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/5F0C2A9E/drive_c/Program Files/Guild Wars 2"),
      .init(source: "Folder · Games", route: .arenanet, bytes: 70_100_000_000, sameDisk: false, hasSettings: false,
            path: "/Volumes/Games/Guild Wars 2"),
    ]
    i.chosenGame = state == "existing-copy" ? i.gameFolders.last : i.gameFolders.first
    if state == "importing" {
      i.operation = .install
      i.phase = .working(.install)
      i.stepIndex = 2
      i.chosenGame = i.gameFolders.last
      i.progress = .init(label: "Guild Wars 2", done: 31_200_000_000, total: 70_100_000_000)
    }
  case "imported":
    // Ready after an import (the summary under the panel)
    st["origin"] = "import"
    i.phase = .succeeded(.install, "Guild Wars 2 is ready: its files were cloned from CrossOver · Steam (no extra space), "
                         + "with your game settings. Steam may check the files at the first Play. Press Play.")
  case "uninstalling":
    i.operation = .uninstall
    i.phase = .working(.uninstall)
    i.stepIndex = 1
  case let s where s.hasPrefix("session-"):
    // after Play: the start's stages, Playing, Steam closing after the game (Session.swift)
    st["busy"] = "steam"
    // (ArenaNet's status while its game runs: game=no, busy=game; Steam's while it updates or
    // verifies the game: game=no, busy=steam, session=live; the panel must still follow them)
    if s == "session-arenanet" { st["route"] = "arenanet"; st["game"] = "no"; st["busy"] = "game" }
    if s == "session-steam-update" { st["game"] = "no"; st["busy"] = "steam"; st["session"] = "live" }
    i.session = session(String(s.dropFirst(8)))
  default: break
  }
  i.status = st
  return i
}

// A session as gw2om.sh session-status would report it
@MainActor
func session(_ state: String) -> Installer.LaunchSession {
  var s = Installer.LaunchSession(fromPlay: true)
  var v = ["route": "steam", "steam": "bg", "game": "no", "closing": "no", "quit_steam": "yes", "elapsed": "42",
           "limiter_hint": "no", "limiter_value": "", "detail": "", "progress": "", "game_elapsed": ""]
  var stage: Installer.Stage? = .checkingFiles
  switch state {
  case "starting", "steam-update":
    // as the design: Steam signed in, then checks the game's files
    v["detail"] = "Steam verifies Guild Wars 2 · 64%"; v["progress"] = "64"
  case "updating":
    stage = .updatingSteam; v["detail"] = "Steam updates itself · 23%"; v["progress"] = "23"; v["elapsed"] = "12"
  case "signing-in":
    // before the first sign-in: Steam's window shows
    stage = .signingIn; v["steam"] = "window"; v["quit_steam"] = "no"; v["elapsed"] = "18"
  case "loading":
    stage = .loading; v["game"] = "yes"; v["elapsed"] = "71"
  case "arenanet":
    stage = .startingGame; v["route"] = "arenanet"; v["steam"] = "none"; v["quit_steam"] = "no"; v["game"] = "yes"
    v["elapsed"] = "6"
  case "playing":
    stage = .playing; v["game"] = "yes"; v["game_elapsed"] = "72"; v["limiter_hint"] = "yes"; v["limiter_value"] = "60"
  case "playing-nohint":
    stage = .playing; v["game"] = "yes"; v["game_elapsed"] = "3725"; v["quit_steam"] = "no"
  case "closing":
    stage = nil; v["closing"] = "yes"; s.gameSeen = true
  default: break
  }
  s.values = v
  s.stage = stage
  if state == "starting" || state == "steam-update" { s.seen = [.startingSteam, .signingIn, .checkingFiles] }
  if let stage { s.seen.insert(stage) }
  return s
}

@MainActor
func settings(_ extra: [String: String] = [:]) -> GameSettings {
  let s = GameSettings()
  s.preview(["installed": "yes", "running": "no", "retina": "on", "fpscap": "off", "metal": "3", "metalfx": "off", "hud": "off",
             "warm": "on", "fastlocks": "off", "ncpu": "8", "uiscale": "off", "uiscale_addon": "off",
             "uiscale_size": "1.75", "uiscale_sans": "on", "uiscale_cinema": "off", "gamemode": "on", "launchopts": "",
             "route": "steam", "updates": "off", "debug": "off", "steambg": "on", "quitsteam": "on", "cpus": "12",
             "steam_login": "no", "rawmouse": "on", "mousespeed": "1", "dxmt": "fork", "wine": "mine", "jobwakes": "on",
             "eventpool": "on", "macdrv": "mine", "launcherframes": "off",
             "arcdps": "off", "arcdps_state": "off",
             "arcdps_foreign": ""].merging(engineStates) { $1 }.merging(extra) { $1 })
  return s
}

// The states and notes gw2om.sh settings prints on this line (setting_state, setting_note; the
// sandbox suite pins them there): the greyed rows with their reasons, the untested notes
let engineStates: [String: String] = [
  "mousespeed_state": "off:My Mac driver in this app (jdrly/wine d831f808236) doesn't have this switch.",
  "gamemode_state": "off:The engine's loader is a Game Mode app. Nothing to switch.",
  "uiscale_note": "Untested on this engine.", "uiscale_size_note": "Untested on this engine.",
  "uiscale_sans_note": "Untested on this engine.", "uiscale_cinema_note": "A code patch, untested under FEX.",
  "arcdps_note": "A code patch, untested under FEX.",
]

@MainActor
func renderAll(_ dir: URL, exports: URL?) async {
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let size = MainView.designSize
  let mains: [(String, String, Bool, String?)] = [
    ("main-choose-light", "choose", false, "1-choose-install.png"),
    ("main-installing-light", "installing", false, "2-installing.png"),
    ("main-ready-light", "ready", false, "3-ready-to-play.png"),
    ("main-ready-dark", "ready", true, "5-ready-to-play-dark.png"),
    ("main-ready-repair-light", "ready-repair", false, nil),
    ("main-ready-engine-light", "ready-engine", false, nil),
    ("main-ready-mixed-light", "ready-mixed", false, nil),
    ("main-ready-other-light", "ready-other", false, nil),
    ("main-ready-fex-light", "ready-fex", false, nil),
    ("main-fresh-old-macos-light", "fresh-old-macos", false, nil),
    ("main-choose-dark", "choose", true, nil),
    ("main-installing-dark", "installing", true, nil),
    ("main-fresh-light", "fresh", false, nil),
    ("main-arenanet-light", "arenanet", false, nil),
    ("main-waiting-dark", "waiting", true, nil),
    ("main-waiting-light", "waiting", false, nil),
    ("main-failed-light", "failed", false, nil),
    ("main-uninstalling-light", "uninstalling", false, nil),
    ("main-existing-light", "existing", false, nil),
    ("main-existing-dark", "existing", true, nil),
    ("main-existing-copy-light", "existing-copy", false, nil),
    ("main-existing-none-light", "existing-none", false, nil),
    ("main-arenanet-dark", "arenanet", true, nil),
    ("main-importing-light", "importing", false, nil),
    ("main-imported-light", "imported", false, nil),
    ("main-starting-light", "session-starting", false, "7-starting.png"),
    ("main-starting-dark", "session-starting", true, "7-starting-dark.png"),
    ("main-playing-light", "session-playing", false, "8-playing.png"),
    ("main-playing-dark", "session-playing", true, "8-playing-dark.png"),
    ("main-closing-light", "session-closing", false, nil),
    ("main-closing-dark", "session-closing", true, nil),
    ("main-starting-updating-light", "session-updating", false, nil),
    ("main-starting-signing-in-light", "session-signing-in", false, nil),
    ("main-starting-loading-dark", "session-loading", true, nil),
    ("main-starting-arenanet-light", "session-arenanet", false, nil),
    ("main-playing-nohint-light", "session-playing-nohint", false, nil),
    ("main-starting-steam-update-light", "session-steam-update", false, nil),
  ]
  // the panel each session state must show (a model check: a wrong one fails the run)
  let panels: [String: Installer.Panel] = ["session-starting": .starting, "session-updating": .starting,
    "session-signing-in": .starting, "session-loading": .starting, "session-arenanet": .starting,
    "session-playing": .playing, "session-playing-nohint": .playing, "session-closing": .ready,
    "session-steam-update": .starting]
  // the Engine and Graphics checks' texts for the files gw2om.sh status can report (a model check)
  do {
    let engine = "Mach9 0.3.1 · Wine 11.21"
    let other = ["wine_file": "other", "wine_commit": "", "wine_release": ""]
    let cases: [(String, [String: String], String, String)] = [
      ("ready", [:], "Wine 11.21 · d831f80", "DXMT 0.80 · 2483559"),
      ("ready-engine", [:], engine, "DXMT · d903db8"),
      ("ready-mixed", [:], "Mach9 0.3.1 · ntdll d831f80", "DXMT 0.80 · 2483559"),
      ("ready-mixed", other, "Mach9 0.3.1 · another ntdll", "DXMT 0.80 · 2483559"),
      ("ready-other", [:], "another ntdll · winemac d831f80", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["macdrv_file": "mine", "macdrv_commit": "d831f808236c", "macdrv_release": "11.21"],
       "Mach9 0.3.1 · winemac d831f80", "DXMT · d903db8"),
      ("ready", ["macdrv_commit": "1a2b3c4d5e6f"], "ntdll d831f80 · winemac 1a2b3c4", "DXMT 0.80 · 2483559"),
      ("ready", ["macdrv_file": "other", "macdrv_commit": ""], "ntdll d831f80 · another winemac", "DXMT 0.80 · 2483559"),
      ("ready", other.merging(["macdrv_file": "other", "macdrv_commit": ""]) { $1 },
       "another ntdll · another winemac", "DXMT 0.80 · 2483559"),
      ("ready", ["wine_release": "", "dxmt_release": ""], "Wine · d831f80", "DXMT · 2483559"),
      ("ready-fex", [:], "Wine 11.21 · d831f80 · FEX bff3f7c", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["fex_file": "mine", "fex_commit": "bff3f7c3686b"], "\(engine) · FEX bff3f7c", "DXMT · d903db8"),
      ("ready-fex", ["fex_file": "mix", "fex_commit": ""], "Wine 11.21 · d831f80", "DXMT 0.80 · 2483559"),
      ("ready", ["macdrv_file": "mix", "macdrv_commit": ""], "ntdll d831f80 · winemac and win32u mixed", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["macdrv_file": "mix", "macdrv_commit": ""], "Mach9 0.3.1 · winemac and win32u mixed", "DXMT · d903db8"),
    ]
    for (state, extra, wantWine, wantDXMT) in cases {
      let s = installer(state).status.merging(extra) { $1 }
      let wine = ThisMac.wine(s, engine: engine), dxmt = ThisMac.dxmt(s)
      guard wine == wantWine, dxmt == wantDXMT else {
        print("FAIL the checks' texts, \(state) \(extra): \"\(wine)\", \"\(dxmt)\", not \"\(wantWine)\", \"\(wantDXMT)\"")
        exit(1)
      }
    }
  }
  // the Graphics check with the tree in place: the Metal row's choice after my fork, none after the
  // engine's own or from a status without it
  do {
    let ready = installer("ready").status
    let cases: [([String: String], String)] = [
      (ready, "DXMT 0.80 · 2483559 · Metal 3"),
      (ready.merging(["metal": "4"]) { $1 }, "DXMT 0.80 · 2483559 · Metal 4"),
      (installer("ready-engine").status.merging(["metal": "4"]) { $1 }, "DXMT · d903db8"),
      (ready.filter { $0.key != "metal" }, "DXMT 0.80 · 2483559"),
    ]
    for (s, want) in cases where ThisMac.dxmtMetal(s) != want {
      print("FAIL the Graphics check's text: \"\(ThisMac.dxmtMetal(s))\", not \"\(want)\"")
      exit(1)
    }
  }
  for (state, want) in panels where installer(state).panel != want {
    print("FAIL \(state): the panel is \(installer(state).panel), not \(want)")
    exit(1)
  }
  // the session as the poller follows it: a restart's gap (the watcher's grace) keeps the session
  // and its polling, the game back shows Playing again, the watcher's end ends it
  do {
    let i = installer("ready")
    i.session = Installer.LaunchSession(fromPlay: false)
    let steps: [([String: String], Bool, Installer.Panel)] = [
      (["stage": "playing", "game": "yes", "watching": "yes"], true, .playing),
      (["stage": "none", "game": "no", "closing": "no", "watching": "yes"], true, .ready),
      (["stage": "loading", "game": "yes", "watching": "yes"], true, .starting),
      (["stage": "playing", "game": "yes", "watching": "yes"], true, .playing),
      (["stage": "none", "game": "no", "closing": "yes", "watching": "yes"], true, .ready),
      (["stage": "none", "game": "no", "closing": "no", "watching": "no"], false, .ready),
    ]
    for (n, (values, goesOn, panel)) in steps.enumerated() {
      let on = i.applySession(values)
      guard on == goesOn, (i.session != nil) == goesOn, i.panel == panel else {
        print("FAIL the session model, step \(n + 1): polling \(on), the panel \(i.panel), not \(goesOn) and \(panel)")
        exit(1)
      }
    }
  }
  // a second Play while the poller still follows the first (the watcher's grace): the poller is
  // replaced (its in-flight result dropped by generation) and the new one counts from the new Play
  do {
    let i = installer("ready")
    i.followSession(fromPlay: true)
    i.session?.started = Date(timeIntervalSince1970: 1_000)
    let old = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
    i.sessionTask = old
    let generation = i.sessionGeneration
    i.applySession(["stage": "none", "game": "no", "closing": "no", "watching": "yes"])
    i.followSession(fromPlay: true)
    let since = Int(i.session?.started.timeIntervalSince1970 ?? 0)
    guard old.isCancelled, i.sessionGeneration > generation, since > 1_000,
          i.sessionStatusArguments == ["session-status", "--since", String(since)], i.panel == .starting else {
      print("FAIL a second Play during the grace: the poller \(old.isCancelled ? "replaced" : "kept"), "
            + "\(i.sessionStatusArguments), the panel \(i.panel)")
      exit(1)
    }
  }
  // the window opened while Steam updates the game (status: finished, game=no, busy=steam,
  // session=live, no session followed yet): still ready, so it picks the session up; Steam on its
  // own (session=none) and a missing game outside a session are not
  do {
    let base = ["installed": "yes", "stage": "finished", "route": "steam", "game": "no", "busy": "steam"]
    for (extra, want) in [(["session": "live"], true), (["session": "none"], false), ([:], false)] {
      let i = Installer()
      i.status = base.merging(extra) { $1 }
      guard i.ready == want, i.gameInstalled == want else {
        print("FAIL Steam updating the game, \(extra): ready \(i.ready), not \(want)")
        exit(1)
      }
    }
  }
  for (name, state, dark, design) in mains {
    let rep = await render(MainView(installer: installer(state), settings: settings()), size: size, dark: dark)
    write(rep, dir.appendingPathComponent(name + ".png"))
    if let exports, let design { compare(design: exports.appendingPathComponent(design), render: rep,
                                         to: dir.appendingPathComponent("compare-" + name + ".png")) }
  }
  for pane in SettingsPane.allCases {
    for dark in [false, true] where !dark || [.graphics, .performance, .interface, .game, .mouse].contains(pane) {
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
  // arcdps in the Interface pane: on, downloading, another addon's d3d11.dll in its place, just placed
  UserDefaults.standard.set(SettingsPane.interface.rawValue, forKey: SettingsView.selectedPaneKey)
  let arcdps: [(String, Bool, [String: String], (GameSettings) -> Void)] = [
    ("on", false, ["arcdps": "on", "arcdps_state": "on"], { _ in }),
    ("on", true, ["arcdps": "on", "arcdps_state": "on"], { _ in }),
    ("downloading", false, ["arcdps": "on"], { s in
      s.arcdpsWorking = true
      s.arcdpsProgress = .init(label: "arcdps", done: 620_000, total: 1_506_304)
    }),
    ("downloading", true, ["arcdps": "on"], { s in
      s.arcdpsWorking = true
      s.arcdpsProgress = .init(label: "arcdps", done: 620_000, total: 1_506_304)
    }),
    ("foreign", false, ["arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("foreign", true, ["arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("placed", false, ["arcdps": "on", "arcdps_state": "on"], { s in
      s.arcdpsResult = "arcdps is in the game folder (d3d11.dll from deltaconnected.com). It loads the next time the game starts, and from then on it updates itself."
    }),
  ]
  for (name, dark, values, adjust) in arcdps {
    let s = settings(values)
    adjust(s)
    write(await render(SettingsView(settings: s), size: SettingsView.designSize, dark: dark),
          dir.appendingPathComponent("settings-interface-arcdps-\(name)-\(dark ? "dark" : "light").png"))
  }
  // the About panel's content as AppKit's standard panel lays it out: the icon, the name, the
  // version and the credits (AppActions.aboutOptions, what the menu's About item shows)
  for dark in [false, true] {
    let about = AboutRender(options: AppActions.aboutOptions(credits: Installer().credits))
    write(await render(about, size: CGSize(width: 300, height: 470), dark: dark),
          dir.appendingPathComponent("about-\(dark ? "dark" : "light").png"))
  }
  for dark in [false, true] {
    let sheet = InterfaceWarning(isPresented: .constant(true)) {}
    write(await render(sheet, size: CGSize(width: 460, height: 300), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-interface-warning-\(dark ? "dark" : "light").png"))
    let arcSheet = ArcdpsWarning(isPresented: .constant(true)) {}
    write(await render(arcSheet, size: CGSize(width: 460, height: 248), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-arcdps-warning-\(dark ? "dark" : "light").png"))
  }
}

// MARK: - The About panel

struct AboutRender: View {
  let options: [NSApplication.AboutPanelOptionKey: Any]
  var body: some View {
    VStack(spacing: 6) {
      Image(nsImage: NSImage(contentsOf: Brand.resources.appendingPathComponent("AppIcon.icns")) ?? NSImage())
        .resizable().frame(width: 64, height: 64)
        .padding(.top, 34)
      Text(options[.applicationName] as? String ?? "?").font(.system(size: 14, weight: .bold))
      Text("Version \(options[.applicationVersion] as? String ?? "?")").font(.system(size: 10))
        .foregroundStyle(.secondary)
      Credits(text: options[.credits] as? NSAttributedString ?? NSAttributedString())
        .frame(width: 260)
        .padding(.top, 8)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  struct Credits: NSViewRepresentable {
    let text: NSAttributedString
    func makeNSView(context: Context) -> NSTextField {
      let field = NSTextField(labelWithAttributedString: text)
      field.maximumNumberOfLines = 0
      field.preferredMaxLayoutWidth = 260
      return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {}
  }
}
