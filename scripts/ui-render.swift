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
    "version": "0.2.0-dev.2", "engine": "mach9-v0.4.0", "engine_title": "Mach9 0.4.0 · Wine 11.21",
    "engine_dxmt": "10e27aed3f5", "dxmt": "fork", "dxmt_tree": "fork", "dxmt_version": "v0.80-489-g2483559",
    "dxmt_release": "0.80", "dxmt_commit": "2483559", "metal": "4",
    "wine": "mine", "wine_ready": "yes", "wine_file": "mine", "wine_commit": "d831f808236c", "wine_release": "11.21",
    "wine_build": "d831f808236c",
    "macdrv": "mine", "macdrv_ready": "yes", "macdrv_file": "mine", "macdrv_commit": "d831f808236c", "macdrv_release": "11.21",
    "macdrv_build": "d831f808236c",
    "fex": "engine", "fex_ready": "yes", "fex_file": "engine", "fex_commit": "597e7ccbedd", "fex_build": "bff3f7c3686b",
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
                     "wine_commit": "501796b0ed1", "wine_release": "", "macdrv": "engine", "macdrv_file": "engine",
                     "macdrv_commit": "501796b0ed1", "macdrv_release": ""]) { $1 }
  case "ready-mixed":
    // my ntdll.so next to the engine's own winemac.so
    st = st.merging(["macdrv": "engine", "macdrv_file": "engine", "macdrv_commit": "501796b0ed1",
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
  case "move-waiting", "moving", "move-failed":
    // the first start after the update from 0.1: the move waits for 0.1's Steam, runs (Steam's
    // folder copied from another disk), or failed
    st = st.merging(["installed": "no", "engine_installed": "no", "graphics": "no", "game": "no", "stage": "none",
                     "steam": "no", "route": "", "installed_version": "", "old_install": "yes", "move": "yes",
                     "move_route": "steam", "move_busy": "none", "move_wait": ""]) { $1 }
    i.operation = .move
    if state == "move-waiting" {
      st["move_busy"] = "steam"
      st["move_wait"] = "Steam is running in GW2 on Mac 0.1. Quit Steam there (Steam > Exit), and the move starts."
      i.phase = .waitingForOld
    } else if state == "moving" {
      i.phase = .working(.move)
      i.stepIndex = 3
      i.progress = .init(label: "Steam and Guild Wars 2", done: 31_200_000_000, total: 72_400_000_000)
    } else {
      i.phase = .failed(.move, "The download of the Wine engine failed (curl status 6). Check your internet connection and try again.")
    }
  case "moved":
    // Ready after the move (the summary under the panel)
    st = st.merging(["origin": "move", "old_install": "yes", "move": "no", "move_record": "moved"]) { $1 }
    i.phase = .succeeded(.move, "Your install moved from GW2 on Mac 0.1: Steam with Guild Wars 2 in its library (cloned, no extra space), "
                         + "your game settings, your addons as they were (arcdps, ReShade with your presets) and your settings. "
                         + "Changed from GW2 on Mac 0.1: Faster locks is off, this version's default. Steam may ask you to sign in once. "
                         + "GW2 on Mac 0.1 stays as it was. Press Play.")
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
  s.preview(["installed": "yes", "running": "no", "retina": "on", "fpscap": "off", "vsync": "on", "metal": "4", "metalfx": "off", "hud": "off",
             "warm": "on", "fastlocks": "off", "ncpu": "8", "uiscale": "off", "uiscale_addon": "off",
             "uiscale_size": "1.75", "uiscale_sans": "on", "uiscale_cinema": "off", "launchopts": "",
             "route": "steam", "updates": "off", "debug": "off", "steambg": "on", "quitsteam": "on", "cpus": "12",
             "steam_login": "no", "rawmouse": "on", "mousespeed": "1", "dxmt": "fork", "wine": "mine", "jobwakes": "on",
             "eventpool": "on", "macdrv": "mine", "launcherframes": "off",
             "arcdps": "off", "arcdps_state": "off",
             "arcdps_foreign": "", "reshade": "off", "reshade_state": "off", "reshade_version": "6.8.0",
             "reshade_dll": "", "reshade_blocker": "", "reshade_folder": "", "addons_layout": "together"].merging(engineStates) { $1 }.merging(extra) { $1 })
  return s
}

// The states gw2om.sh settings prints on this line (setting_state; the sandbox suite pins them
// there): the greyed rows with their reasons
let engineStates: [String: String] = [
  "mousespeed_state": "off:My Mac driver in this app (jdrly/wine d831f808236) doesn't have this switch.",
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
    ("main-ready-fex-dark", "ready-fex", true, nil),
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
    ("main-move-waiting-light", "move-waiting", false, nil),
    ("main-move-waiting-dark", "move-waiting", true, nil),
    ("main-moving-light", "moving", false, nil),
    ("main-moving-dark", "moving", true, nil),
    ("main-move-failed-light", "move-failed", false, nil),
    ("main-moved-light", "moved", false, nil),
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
    "session-steam-update": .starting,
    "move-waiting": .installing, "moving": .installing, "move-failed": .installing, "moved": .ready]
  // what the window does about the move from 0.1 for a status (a model check): start it, wait for
  // 0.1, or nothing (installed, no move, a Mac below the engine's macOS, a move that failed or was
  // cancelled, whether 0.1 runs or not)
  do {
    let base = ["installed": "no", "move": "yes", "move_busy": "none", "macos_ok": "yes", "arch": "arm64"]
    let failed = Installer.Phase.failed(.move, "x")
    let cases: [([String: String], Installer.Phase, Installer.MoveNext)] = [
      ([:], .idle, .start), (["move_busy": "steam"], .idle, .wait), (["move_busy": "game"], .waitingForOld, .wait),
      ([:], .waitingForOld, .start), ([:], failed, .none), (["move_busy": "steam"], failed, .none),
      (["installed": "yes"], .idle, .none), (["move": "no"], .idle, .none), (["macos_ok": "no"], .idle, .none),
    ]
    for (extra, phase, want) in cases where Installer.moveNext(base.merging(extra) { $1 }, phase: phase) != want {
      print("FAIL the move's next step, \(extra) \(phase): \(Installer.moveNext(base.merging(extra) { $1 }, phase: phase)), not \(want)")
      exit(1)
    }
  }
  // the Engine and Graphics checks' texts for the files gw2om.sh status can report (a model check)
  do {
    let engine = "Mach9 0.4.0 · Wine 11.21"
    let other = ["wine_file": "other", "wine_commit": "", "wine_release": ""]
    let cases: [(String, [String: String], String, String)] = [
      ("ready", [:], "Wine 11.21 · d831f80", "DXMT 0.80 · 2483559"),
      ("ready-engine", [:], engine, "DXMT · 10e27ae"),
      ("ready-mixed", [:], "Mach9 0.4.0 · ntdll d831f80", "DXMT 0.80 · 2483559"),
      ("ready-mixed", other, "Mach9 0.4.0 · another ntdll", "DXMT 0.80 · 2483559"),
      ("ready-other", [:], "another ntdll · winemac d831f80", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["macdrv_file": "mine", "macdrv_commit": "d831f808236c", "macdrv_release": "11.21"],
       "Mach9 0.4.0 · winemac d831f80", "DXMT · 10e27ae"),
      ("ready", ["macdrv_commit": "1a2b3c4d5e6f"], "ntdll d831f80 · winemac 1a2b3c4", "DXMT 0.80 · 2483559"),
      ("ready", ["macdrv_file": "other", "macdrv_commit": ""], "ntdll d831f80 · another winemac", "DXMT 0.80 · 2483559"),
      ("ready", other.merging(["macdrv_file": "other", "macdrv_commit": ""]) { $1 },
       "another ntdll · another winemac", "DXMT 0.80 · 2483559"),
      ("ready", ["wine_release": "", "dxmt_release": ""], "Wine · d831f80", "DXMT · 2483559"),
      ("ready-fex", [:], "Wine 11.21 · d831f80 · FEX bff3f7c", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["fex_file": "mine", "fex_commit": "bff3f7c3686b"], "\(engine) · FEX bff3f7c", "DXMT · 10e27ae"),
      ("ready-fex", ["fex_file": "mix", "fex_commit": ""], "Wine 11.21 · d831f80", "DXMT 0.80 · 2483559"),
      ("ready", ["macdrv_file": "mix", "macdrv_commit": ""], "ntdll d831f80 · winemac and win32u mixed", "DXMT 0.80 · 2483559"),
      ("ready-engine", ["macdrv_file": "mix", "macdrv_commit": ""], "Mach9 0.4.0 · winemac and win32u mixed", "DXMT · 10e27ae"),
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
      (ready, "DXMT 0.80 · 2483559 · Metal 4"),
      (ready.merging(["metal": "3"]) { $1 }, "DXMT 0.80 · 2483559 · Metal 3"),
      (installer("ready-engine").status, "DXMT · 10e27ae"),
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
  // The checks' long texts, each in full, light and dark (#134): the Engine's from 38 characters
  // on, its Repair, and every check at its longest at once but Disk space, whose "needs" shows only
  // without the game (main-choose). The Engine text a render shows is checked first.
  do {
    let fex = ["fex": "mine", "fex_file": "mine", "fex_commit": "bff3f7c3686b"]
    let others = ["wine_file": "other", "wine_commit": "", "wine_release": "", "macdrv_file": "other",
                  "macdrv_commit": "", "macdrv_release": ""]
    let longest = fex.merging([
      "wine_ready": "switch", "wine_file": "other", "wine_commit": "", "wine_release": "",
      "macdrv_ready": "switch", "macdrv_file": "mix", "macdrv_commit": "", "macdrv_release": "",
      "graphics": "switch", "macos": "26.3", "macos_ok": "no", "route": "arenanet"]) { $1 }
    let long: [(String, String, [String: String], String)] = [
      ("engine-own-fex", "ready-engine", fex, "Mach9 0.4.0 · Wine 11.21 · FEX bff3f7c"),
      ("engine-switch", "ready", ["wine_ready": "switch"], "Wine 11.21 · d831f80 · at the next Play"),
      ("engine-ntdll-fex", "ready-mixed", fex, "Mach9 0.4.0 · ntdll d831f80 · FEX bff3f7c"),
      ("engine-winemac-fex", "ready-engine",
       fex.merging(["macdrv_file": "mine", "macdrv_commit": "d831f808236c", "macdrv_release": "11.21"]) { $1 },
       "Mach9 0.4.0 · winemac d831f80 · FEX bff3f7c"),
      ("engine-two-builds-fex", "ready", fex.merging(["macdrv_commit": "1a2b3c4d5e6f"]) { $1 },
       "ntdll d831f80 · winemac 1a2b3c4 · FEX bff3f7c"),
      ("engine-others-fex", "ready", fex.merging(others) { $1 }, "another ntdll · another winemac · FEX bff3f7c"),
      ("engine-switch-fex", "ready-fex", ["wine_ready": "switch"], "Wine 11.21 · d831f80 · FEX bff3f7c · at the next Play"),
      ("engine-repair", "ready",
       fex.merging(others) { $1 }.merging(["wine_ready": "other", "macdrv_ready": "other", "fex_ready": "other",
                                           "fex_file": "other"]) { $1 },
       "Mach9 0.4.0 · ntdll and winemac and FEX needs Repair"),
      ("longest", "ready", longest, "another ntdll · winemac and win32u mixed · FEX bff3f7c · at the next Play"),
    ]
    for (name, state, extra, want) in long {
      for dark in [false, true] {
        let i = installer(state)
        i.status = i.status.merging(extra) { $1 }
        let engine = ThisMac(installer: i).checks.first { $0.id == "Engine" }?.value ?? ""
        guard engine == want else {
          print("FAIL the Engine check in main-\(name): \"\(engine)\", not \"\(want)\"")
          exit(1)
        }
        write(await render(MainView(installer: i, settings: settings()), size: size, dark: dark),
              dir.appendingPathComponent("main-\(name)-\(dark ? "dark" : "light").png"))
      }
    }
  }
  for pane in SettingsPane.allCases {
    for dark in [false, true] where !dark || [.graphics, .performance, .interface, .game, .mouse].contains(pane) {
      UserDefaults.standard.set(pane.rawValue, forKey: SettingsView.selectedPaneKey)
      let name = "settings-\(pane.rawValue)-\(dark ? "dark" : "light")"
      let rep = await render(SettingsView(settings: settings()), size: SettingsView.designSize, dark: dark)
      write(rep, dir.appendingPathComponent(name + ".png"))
      // (Troubleshooting with Start fresh: after a move from 0.1, and before one, nothing installed)
      if pane == .troubleshooting {
        for (n, extra) in [("moved", ["old_install": "yes", "move_record": "moved"]),
                           ("not-installed", ["installed": "no", "old_install": "yes", "move_record": ""])] {
          write(await render(SettingsView(settings: settings(extra)), size: SettingsView.designSize, dark: dark),
                dir.appendingPathComponent("settings-troubleshooting-start-fresh-\(n)-light.png"))
        }
      }
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
      s.arcdps.working = true
      s.arcdps.progress = .init(label: "arcdps", done: 620_000, total: 1_506_304)
    }),
    ("downloading", true, ["arcdps": "on"], { s in
      s.arcdps.working = true
      s.arcdps.progress = .init(label: "arcdps", done: 620_000, total: 1_506_304)
    }),
    ("foreign", false, ["arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("foreign", true, ["arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("placed", false, ["arcdps": "on", "arcdps_state": "on"], { s in
      s.arcdps.result = "arcdps is in the game folder (d3d11.dll from deltaconnected.com). It loads the next time the game starts, and from then on it updates itself."
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
    let arcSheet = AddonWarning.arcdps(isPresented: .constant(true)) {}
    write(await render(arcSheet, size: CGSize(width: 460, height: 248), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-arcdps-warning-\(dark ? "dark" : "light").png"))
    let reshadeSheet = AddonWarning.reshade(isPresented: .constant(true), version: "6.8.0") {}
    write(await render(reshadeSheet, size: CGSize(width: 460, height: 278), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-reshade-warning-\(dark ? "dark" : "light").png"))
    let presetSheet = AddonWarning.preset(isPresented: .constant(true), name: "Golden Hour.ini") {}
    write(await render(presetSheet, size: CGSize(width: 460, height: 172), dark: dark, chrome: false),
          dir.appendingPathComponent("sheet-reshade-preset-\(dark ? "dark" : "light").png"))
  }
  // A row's line of buttons with two of them, at the pane's width in the narrowest window (the
  // ReShade row's, alone)
  let rowWidth = SettingsView.designSize.width - 214 - 48 + 24
  for dark in [false, true] {
    let row = SettingsGroup {
      SettingRow("ReShade", "Post-processing effects by crosire, drawn over the finished picture. Downloads ReShade 6.8.0 from reshade.me. Open its menu in the game with the Home key (fn + Left Arrow on a MacBook).") {
        InkSwitch(isOn: .constant(true))
      } buttons: {
        SmallButton("Open ReShade folder", icon: "folder-open") {}
        SmallButton("Add preset or shaders…", icon: "file-down") {}
      }
    }
    // (a fixed size, as the sheets have)
    .padding(12)
    .frame(width: rowWidth, height: 160, alignment: .top)
    .background(Brand.bg)
    write(await render(row, size: CGSize(width: rowWidth, height: 160), dark: dark, chrome: false),
          dir.appendingPathComponent("row-two-buttons-\(dark ? "dark" : "light").png"))
  }
  // ReShade in the Interface pane: off with its folder from an earlier time (the pane's own render
  // has no folder yet), downloading, just placed, both on (ReShade loads arcdps), another ReShade,
  // another program's file in the way (alone, and next to arcdps), the game running; in the
  // exclusive layout each addon waiting for the other. (The folder: any one that exists.)
  let folder = dir.path
  // (an import's report as gw2om.sh gives it for a preset with many missing effects: five names,
  // then the number of the others)
  let report = "Added 1 preset to Presets, 148 shader files to Shaders/Golden Hour and 12 images to Textures/Golden Hour. "
    + "This preset uses 14 effects. 9 are missing: qUINT_mxao.fx, qUINT_lightroom.fx, PD80_04_Contrast_Brightness_Saturation.fx, "
    + "PD80_03_Filmic_Adaptation.fx, iMMERSE_Sharpen.fx and 4 more. qUINT_mxao.fx reads the depth buffer: it stays off in "
    + "online games with this build of ReShade."
  let reshade: [(String, Bool, [String: String], (GameSettings) -> Void)] = [
    ("off", false, ["reshade_folder": folder], { _ in }),
    ("off", true, ["reshade_folder": folder], { _ in }),
    ("downloading", false, ["reshade": "on"], { s in
      s.reshade.working = true
      s.reshade.progress = .init(label: "ReShade", done: 1_650_000, total: 4_075_064)
    }),
    ("downloading", true, ["reshade": "on"], { s in
      s.reshade.working = true
      s.reshade.progress = .init(label: "ReShade's standard effects", done: 2_300_000, total: 0)
    }),
    ("on", false, ["reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll", "reshade_folder": folder], { s in
      s.reshade.result = "ReShade 6.8.0 is in the game folder as d3d11.dll. It loads the next time the game starts."
    }),
    ("on", true, ["reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll", "reshade_folder": folder], { _ in }),
    ("both-on", false, ["reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll", "reshade_folder": folder,
                        "arcdps": "on", "arcdps_state": "on", "arcdps_dll": "addons/arcdps/chain/d3d11.dll"], { s in
      s.reshade.result = "ReShade 6.8.0 is in the game folder as d3d11.dll. It loads the next time the game starts. ReShade loads arcdps itself now, so both load."
    }),
    ("both-on", true, ["reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll", "reshade_folder": folder,
                       "arcdps": "on", "arcdps_state": "on", "arcdps_dll": "addons/arcdps/chain/d3d11.dll"], { _ in }),

    ("foreign", false, ["reshade_state": "foreign", "reshade_dll": "d3d11.dll",
                        "arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("blocked-other", false, ["reshade_state": "blocked", "reshade_blocker": "d3d11.dll",
                              "arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("blocked-nexus", false, ["reshade_state": "blocked", "reshade_blocker": "d3d11.dll", "arcdps": "on", "arcdps_state": "on",
                              "arcdps_foreign": "d3d11.dll"], { _ in }),
    ("running", false, ["running": "yes", "reshade": "on", "reshade_state": "on", "reshade_folder": folder,
                        "arcdps": "on", "arcdps_state": "on"], { _ in }),
    ("exclusive-arcdps-in", false, ["addons_layout": "exclusive", "reshade_state": "blocked", "reshade_blocker": "d3d11.dll",
                                    "arcdps": "on", "arcdps_state": "on"], { _ in }),
    ("exclusive-arcdps-in", true, ["addons_layout": "exclusive", "reshade_state": "blocked", "reshade_blocker": "d3d11.dll",
                                   "arcdps": "on", "arcdps_state": "on"], { _ in }),
    ("exclusive-reshade-in", false, ["addons_layout": "exclusive", "reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll",
                                     "reshade_folder": folder, "arcdps_state": "foreign", "arcdps_foreign": "d3d11.dll"], { _ in }),
    // after an import with ReShade off, and while the game runs (under the running note)
    ("report", false, ["reshade_folder": folder], { s in s.reshadeReport = report }),
    ("report", true, ["reshade_folder": folder], { s in s.reshadeReport = report }),
    ("report-running", false, ["running": "yes", "reshade": "on", "reshade_state": "on", "reshade_dll": "d3d11.dll",
                               "reshade_folder": folder], { s in
      s.reshadeReport = report + " Guild Wars 2 is running: pick the preset in ReShade's menu (Home key)."
    }),
    ("importing", false, ["reshade_folder": folder], { s in s.reshadeImporting = true }),
  ]
  for (name, dark, values, adjust) in reshade {
    let s = settings(values)
    adjust(s)
    write(await render(SettingsView(settings: s), size: SettingsView.designSize, dark: dark),
          dir.appendingPathComponent("settings-interface-reshade-\(name)-\(dark ? "dark" : "light").png"))
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
