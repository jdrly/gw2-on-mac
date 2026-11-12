// The main window, as the approved design draws it (its Main — … frames): the
// ink-stroke header with the GW2 / ON MAC wordmark, the tagline and the Unofficial badge; on the
// left this Mac's six checks and what the app does; on the right the painting and one panel:
// choose the install route (Steam or ArenaNet's installer), the install's steps with progress and
// Cancel, Ready (Play, Repair, Settings, Uninstall…), or, after Play, Starting and Playing
// (Session.swift); the disclaimer in the footer.
//
// Light and dark follow the system; each has its own header stroke (Art/header-light.png
// multiplied on parchment, Art/header-dark.png lightened on the dark ink, where its black drops
// out).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
  static let designSize = CGSize(width: 960, height: 652)

  @Bindable var installer: Installer
  let settings: GameSettings
  @Environment(\.openWindow) private var openWindow
  @State private var confirmUninstall = false
  @State private var showLogSheet = false
  @State private var blocked: Blocked?

  struct Blocked: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  var body: some View {
    VStack(spacing: 0) {
      Header()
      HStack(alignment: .top, spacing: 28) {
        VStack(alignment: .leading, spacing: 14) {
          ThisMac(installer: installer)
          Color.clear.frame(height: 4)
          WhatItDoes()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        RightColumn(installer: installer, actions: actions)
          .frame(width: 392)
      }
      .padding(.top, 6)
      .padding(.horizontal, 28)
      .padding(.bottom, 18)
      .frame(maxHeight: .infinity, alignment: .top)
      Footer(repo: installer.credits["repo"] ?? "https://github.com/jdrly/gw2-on-mac")
    }
    .background { WindowBackground() }
    .ignoresSafeArea()
    .frame(minWidth: MainView.designSize.width, minHeight: MainView.designSize.height)
    .animation(.smooth, value: installer.phase)
    .animation(.smooth, value: installer.panel)
    .animation(.smooth, value: installer.status)
    .sheet(isPresented: $showLogSheet) { LogSheet(installer: installer) }
    .onChange(of: installer.closeSheets) { _, _ in
      showLogSheet = false
      confirmUninstall = false
      blocked = nil
    }
    .onChange(of: showLogSheet || confirmUninstall || blocked != nil) { _, open in
      installer.sheetOpen = open
    }
    .alert("Uninstall \(appName)?", isPresented: $confirmUninstall) {
      Button("Uninstall", role: .destructive) { installer.start(.uninstall) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes everything \(appName) created: the Wine engine and the game's bottle. The "
           + "game's files are in the bottle, so they go with it: Guild Wars 2 has to download again if "
           + "you install it later. Its caches go too, DXMT's shader cache with them. Your account, "
           + "characters and Steam library are not affected. The logs are kept.")
    }
    .alert(blocked?.title ?? "", isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } }),
           presenting: blocked) { _ in
      Button("OK", role: .cancel) { blocked = nil }
    } message: { b in
      Text(b.message)
    }
  }

  private var actions: PanelActions {
    PanelActions(
      install: askInstall,
      play: play,
      repair: { askRepair() },
      uninstall: { askUninstall() },
      settings: { settings.reload(); openWindow(id: "settings") },
      showLog: { showLogSheet = true })
  }

  private func askInstall() {
    installer.refresh {
      if let reason = installer.installBlocker {
        blocked = Blocked(title: "Can't install yet", message: reason)
      } else if let reason = busyReason {
        blocked = Blocked(title: "Can't install now", message: reason)
      } else {
        installer.start(.install)
      }
    }
  }

  private func askRepair() {
    installer.refresh {
      if let reason = busyReason {
        blocked = Blocked(title: "Can't repair now", message: reason)
      } else {
        installer.start(.repair)
      }
    }
  }

  private func askUninstall() {
    installer.refresh {
      if let reason = busyReason {
        blocked = Blocked(title: "Can't uninstall now", message: reason)
      } else {
        confirmUninstall = true
      }
    }
  }

  // Install, Repair and Uninstall wait for the game, Steam and the bottle's Wine to quit
  private var busyReason: String? {
    let detail = installer.status["busy_detail"].map { $0.isEmpty ? "" : " (\($0))" } ?? ""
    switch installer.busy {
    case "game": return "Guild Wars 2 is running. Quit it first."
    case "steam": return "Steam is running in the game's bottle. Quit Steam first (Steam > Exit)."
    case "installer": return "ArenaNet's installer is running. Let it finish or quit it first."
    case "session": return "The game's Wine is still running\(detail). It ends by itself a few seconds after Steam and the game have quit; try again then."
    default: return nil
    }
  }

  private func play() {
    installer.play { message, started in
      if let message {
        blocked = Blocked(title: started ? "Starting Guild Wars 2" : "Can't start Guild Wars 2", message: message)
      }
    }
  }
}

struct PanelActions {
  let install: () -> Void
  let play: () -> Void
  let repair: () -> Void
  let uninstall: () -> Void
  let settings: () -> Void
  let showLog: () -> Void
}

// MARK: - Background and header

// The window's background: the parchment (or the dark ink), the header's ink stroke and its fade
// into the body. Light: the stroke multiplied on the parchment. Dark: a dark gradient under the
// header and the stroke lightened on it (its black drops out).
struct WindowBackground: View {
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      ZStack(alignment: .topLeading) {
        Brand.bg
        if scheme == .dark {
          LinearGradient(colors: [Color(hex: 0x1E1813), Color(hex: 0x14110E)], startPoint: .top, endPoint: .bottom)
            .frame(width: w, height: 132)
        }
        ArtImage(name: scheme == .dark ? "header-dark.png" : "header-light.png")
          .frame(width: w + 60, height: 190)
          .clipped()
          .offset(x: -30, y: -34)
          .blendMode(scheme == .dark ? .lighten : .multiply)
        LinearGradient(colors: [Brand.bg.opacity(0), Brand.bg], startPoint: .top, endPoint: .bottom)
          .frame(width: w, height: 62)
          .offset(y: 96)
      }
      .compositingGroup()
    }
  }
}

// A chip on the header's ink: an icon and a label on dark glass, for the header's buttons
struct HeaderChip: View {
  let icon: String
  let label: String

  var body: some View {
    HStack(spacing: 6) {
      LucideIcon(name: icon, size: 13).foregroundStyle(Brand.badgeText)
      Text(label).font(.body(12, .semibold)).bodyBox(12).foregroundStyle(Brand.headerText)
    }
    .padding(.vertical, 5).padding(.horizontal, 10)
    .background(Color(hex: 0x1E1813, alpha: 0x99 / 255), in: .rect(cornerRadius: 5))
    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: 0xF6E6C4, alpha: 0x55 / 255), lineWidth: 1))
  }
}

struct Header: View {
  @State private var showNotice = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    ZStack(alignment: .topLeading) {
      Wordmark()
        .offset(x: 36, y: 36)
      Text("Guild Wars 2 for Apple Silicon")
        .font(.head(23))
        .foregroundStyle(Brand.headerText)
        .shadow(color: Brand.headerShadow.opacity(0.7), radius: 3, y: 1)
        .lineLimit(1)
        .offset(x: 186, y: 50)
      HStack(spacing: 8) {
        #if GW2_DEV
        DevBuildBadge()
        #endif
        // I answer questions about the app and addons on Discord. You can report bugs there too.
        // The icon is Lucide's chat bubble, as on gw2onmac.com, not Discord's logo.
        Button { openURL(Support.discord) } label: {
          HeaderChip(icon: "message-circle", label: "Discord")
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Help, arcdps and addon questions, and bug reports: Pharaphobia on Discord")
        .accessibilityLabel("Discord")
        .accessibilityHint("Opens the Discord server for help in your browser")
        Button { showNotice.toggle() } label: {
          HeaderChip(icon: "shield-alert", label: "Unofficial fan project")
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(disclaimer)
        .accessibilityLabel("Unofficial fan project")
        .accessibilityHint("Shows the notice")
        .popover(isPresented: $showNotice, arrowEdge: .bottom) {
          Text("\(appName) is an unofficial fan project. " + disclaimer + " It installs nothing of the "
               + "game itself: Steam or ArenaNet's own installer downloads it.")
            .font(.body(13)).bodyBox(13)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(width: 340)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.top, 22)
      .padding(.trailing, 28)
    }
    .frame(height: 132, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if GW2_DEV
struct DevBuildBadge: View {
  private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
  var body: some View {
    Text("Dev build · \(version)")
      .font(.body(12, .semibold)).bodyBox(12)
      .foregroundStyle(Brand.headerText)
      .padding(.vertical, 5).padding(.horizontal, 10)
      .background(Brand.warning.opacity(0.8), in: .rect(cornerRadius: 5))
  }
}
#endif

// "GW2" in Cinzel over a gold rule and "ON MAC", in cream with a dark-red shadow (on the ink)
struct Wordmark: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("GW2")
        .font(.display(40))
        .tracking(2)
        .foregroundStyle(Brand.headerText)
        .shadow(color: Brand.headerShadow.opacity(0.7), radius: 3, y: 1)
        .frame(height: 40)
      HStack(spacing: 10) {
        Rectangle().fill(Brand.goldRule).frame(width: 28, height: 2)
        Text("ON MAC")
          .font(.display(15))
          .tracking(5)
          .foregroundStyle(Brand.headerText)
          .shadow(color: Brand.headerShadow.opacity(0.9), radius: 2.5, y: 1)
      }
      .frame(height: 20)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(appName)
    .accessibilityAddTraits(.isHeader)
  }
}

struct Footer: View {
  let repo: String
  var body: some View {
    HStack(spacing: 8) {
      Text(disclaimer).foregroundStyle(Brand.fg3)
      Text("·").foregroundStyle(Brand.fg3)
      Link(repo.replacingOccurrences(of: "https://", with: ""), destination: URL(string: repo)!)
        .font(.body(11.5, .semibold)).bodyBox(11.5)
        .foregroundStyle(Brand.accent)
        .pointerStyle(.link)
    }
    .font(.body(11.5)).bodyBox(11.5)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .padding(.vertical, 10)
    .padding(.horizontal, 28)
    .frame(maxWidth: .infinity)
    .overlay(alignment: .top) { Rectangle().fill(Brand.border).frame(height: 1) }
  }
}

// MARK: - This Mac

struct ThisMac: View {
  let installer: Installer

  enum Tone { case good, pending, off, bad }
  struct Check: Identifiable {
    let id: String
    let icon: String
    let value: String
    let tone: Tone
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      InkHeading(title: "This Mac") {
        Text(summary)
          .font(.body(12, .semibold)).bodyBox(12)
          .tracking(0.6)
          .foregroundStyle(Brand.fg3)
          .accessibilityHidden(true)
      }
      VStack(spacing: 0) {
        let all = checks
        ForEach(0..<3) { row in
          HStack(spacing: 0) {
            CheckCell(check: all[row * 2])
            Rectangle().fill(Brand.border).frame(width: 1)
            CheckCell(check: all[row * 2 + 1])
          }
          .fixedSize(horizontal: false, vertical: true)
          if row < 2 { Rectangle().fill(Brand.border).frame(height: 1) }
        }
      }
      .background(Brand.bgRaised)
      .clipShape(.rect(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.border, lineWidth: 1))
    }
  }

  // "4 of 6 ready", "6 checks · all good"
  private var summary: String {
    guard installer.loaded else { return "Checking…" }
    let good = checks.filter { $0.tone == .good }.count
    return good == 6 ? "6 checks · all good" : "\(good) of 6 ready"
  }

  private var checks: [Check] {
    let s = installer.status
    guard installer.loaded else {
      return ["macOS", "Engine", "Graphics", "Game Mode", "Guild Wars 2", "Disk space"].map {
        Check(id: $0, icon: ThisMac.icons[$0]!, value: "Checking…", tone: .off)
      }
    }
    let engine = s["engine_title"] ?? "Mach9 0.3.1 · Wine 11.21"
    let short = engine.components(separatedBy: " · ").first ?? engine
    let libs = [("wine", "ntdll"), ("macdrv", "winemac")]
    let wine = ThisMac.wine(s, engine: engine)
    let switching = libs.contains { s["\($0.0)_ready"] == "switch" }
    let repair = libs.filter { s["\($0.0)_ready"] == "other" }.map { $0.1 }
    let macos = s["macos"] ?? "?"
    let dxmt = ThisMac.dxmt(s)
    let route = installer.installedRoute == .arenanet ? "ArenaNet" : "Steam"
    let game: Check
    if installer.gameInstalled {
      game = Check(id: "Guild Wars 2", icon: "swords", value: "Installed · \(route)", tone: .good)
    } else if installer.phase == .waitingForGame || installer.isOperating && installer.operation != .uninstall {
      game = Check(id: "Guild Wars 2", icon: "swords", value: "Installing…", tone: .pending)
    } else {
      game = Check(id: "Guild Wars 2", icon: "swords", value: "Not installed yet", tone: .off)
    }
    let free = installer.diskFree
    let disk = installer.diskLow
      ? Check(id: "Disk space", icon: "hard-drive",
              value: "\(Installer.gigabytes(free)) free · needs \(Installer.gigabytes(installer.diskNeeded))", tone: .bad)
      : Check(id: "Disk space", icon: "hard-drive", value: free > 0 ? "\(Installer.gigabytes(free)) free" : "Unknown",
              tone: free > 0 ? .good : .off)
    return [
      Check(id: "macOS", icon: "cpu",
            value: installer.macosOK ? macos : "\(macos) · needs \(s["macos_min"] ?? "26.4")",
            tone: installer.macosOK ? .good : .bad),
      // (switch: Settings changed a file while Steam ran; other: neither the engine's nor mine)
      Check(id: "Engine", icon: "wine",
            value: s["engine_installed"] != "yes" ? "\(engine) · not set up"
              : switching ? "\(wine) · at the next Play"
              : !repair.isEmpty ? "\(short) · \(repair.joined(separator: " and ")) needs Repair" : wine,
            tone: s["engine_installed"] != "yes" ? .off : switching ? .pending
              : !repair.isEmpty ? .bad : .good),
      // (switch: Settings changed it while Steam ran; the next Play puts it in)
      Check(id: "Graphics", icon: "sparkles",
            value: s["graphics"] == "yes" ? dxmt
              : s["graphics"] == "switch" ? "\(dxmt) · at the next Play"
              : s["graphics"] == "other" ? "\(dxmt) · needs Repair" : "\(dxmt) · not set up",
            tone: s["graphics"] == "yes" ? .good : s["graphics"] == "switch" ? .pending
              : s["graphics"] == "other" ? .bad : .off),
      // (every Wine process runs as the engine's loader, a Game Mode app: nothing to set up)
      Check(id: "Game Mode", icon: "gamepad-2", value: "The engine's loader",
            tone: s["gamemode"] == "engine" ? .good : .off),
      game,
      disk,
    ]
  }

  static let icons = ["macOS": "cpu", "Engine": "wine", "Graphics": "sparkles", "Game Mode": "gamepad-2",
                      "Guild Wars 2": "swords", "Disk space": "hard-drive"]

  // The Wine the engine runs, from the ntdll.so and winemac.so in it (gw2om.sh status wine_*,
  // macdrv_*), on one line. Both mine from one build: "Wine 11.21 · d831f80", the release and
  // commit of my build. Both the engine's own: the engine's title. One of mine or another file next
  // to the engine's own: "Mach9 0.3.1 · ntdll d831f80", "Mach9 0.3.1 · another winemac". Two that
  // aren't one build of mine: each with its commit, or "another".
  static func wine(_ s: [String: String], engine: String) -> String {
    let short = engine.components(separatedBy: " · ").first ?? engine
    let libs = [("wine", "ntdll"), ("macdrv", "winemac")]
    let commit = { (key: String) in String((s["\(key)_commit"] ?? "").prefix(7)) }
    let named = libs.filter { s["\($0.0)_file"] == "mine" || s["\($0.0)_file"] == "other" }
    let each = named.map { s["\($0.0)_file"] == "mine" ? "\($0.1) \(commit($0.0))" : "another \($0.1)" }
    if named.isEmpty { return engine }
    if named.count == 1 { return "\(short) · \(each[0])" }
    if s["wine_file"] == "mine", s["macdrv_file"] == "mine", commit("wine") == commit("macdrv") {
      let release = s["wine_release"] ?? ""
      return release.isEmpty ? "Wine · \(commit("wine"))" : "Wine \(release) · \(commit("wine"))"
    }
    return each.joined(separator: " · ")
  }

  // The DXMT Settings asks for: my fork, "DXMT 0.80 · 2483559" (the release and commit of my
  // build), or the engine's own, "DXMT · d903db8" (athei/dxmt's commit)
  static func dxmt(_ s: [String: String]) -> String {
    if s["dxmt"] == "engine" { return "DXMT · \((s["engine_dxmt"] ?? "").prefix(7))" }
    let release = s["dxmt_release"] ?? "", commit = (s["dxmt_commit"] ?? "").prefix(7)
    return release.isEmpty ? "DXMT · \(commit)" : "DXMT \(release) · \(commit)"
  }
}

struct CheckCell: View {
  let check: ThisMac.Check

  var body: some View {
    HStack(spacing: 11) {
      ZStack {
        Circle().fill(disc)
        LucideIcon(name: check.icon, size: 16).foregroundStyle(iconColor)
      }
      .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(check.id).font(.body(13, .bold)).bodyBox(13).foregroundStyle(Brand.fg)
        HStack(spacing: 5) {
          Pip(color: pip)
          Text(check.value).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg2).lineLimit(1).truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 11)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var disc: Color {
    switch check.tone {
    case .good, .pending: Brand.goldSoft
    case .off: Brand.surface
    case .bad: Brand.accentSoft
    }
  }
  private var iconColor: Color {
    switch check.tone {
    case .good, .pending: Brand.gold
    case .off: Brand.fg3
    case .bad: Brand.accent
    }
  }
  private var pip: Color {
    switch check.tone {
    case .good: Brand.good
    case .pending: Brand.gold
    case .off: Brand.fg3
    case .bad: Brand.accent
    }
  }
}

// MARK: - What it does

struct WhatItDoes: View {
  private let features: [(String, String, String)] = [
    ("zap", "Direct3D 11 straight to Metal", "My DXMT fork draws the game through Metal 4."),
    ("cpu", "Wine for Apple silicon", "Wine runs natively. FEX translates only the game's own x86 code."),
    ("type", "Sharp text at 4K", "A larger interface drawn from the game's own crisp fonts."),
    ("undo-2", "Yours, and reversible", "Your own Steam or ArenaNet install. Uninstall removes everything."),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      InkHeading("What it does")
      ForEach(0..<2) { row in
        HStack(alignment: .top, spacing: 22) {
          feature(features[row * 2])
          feature(features[row * 2 + 1])
        }
      }
    }
  }

  private func feature(_ f: (String, String, String)) -> some View {
    HStack(alignment: .top, spacing: 10) {
      LucideIcon(name: f.0, size: 18).foregroundStyle(Brand.accent)
      VStack(alignment: .leading, spacing: 3) {
        Text(f.1).font(.head(15.5)).foregroundStyle(Brand.fg).lineLimit(1).minimumScaleFactor(0.85)
        Text(f.2).font(.body(13)).bodyBox(13, 1.3).foregroundStyle(Brand.fg2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.top, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(Brand.border).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Right column

struct RightColumn: View {
  @Bindable var installer: Installer
  let actions: PanelActions

  // The painting stays while the panel leaves room for it (the window's height): the list of
  // existing game files, the drop zone or a long message can take its place
  var body: some View {
    ViewThatFits(in: .vertical) {
      column(painting: true)
      column(painting: false)
    }
  }

  private func column(painting: Bool) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if painting {
        // (lower while the game starts or runs: the stage list takes the room)
        ArtImage(name: "painting.webp")
          .frame(width: 392, height: installer.panel == .starting || installer.panel == .playing ? 110 : 132)
          .clipped()
          .accessibilityLabel("A painted landscape: a traveller on a cliff above a river valley and a city")
      }
      switch installer.panel {
      case .choose: ChoosePanel(installer: installer, actions: actions)
      case .installing: InstallingPanel(installer: installer, actions: actions)
      case .ready: ReadyPanel(installer: installer, actions: actions)
      case .starting: StartingPanel(installer: installer, session: installer.session ?? .init(fromPlay: false))
      case .playing: PlayingPanel(installer: installer, session: installer.session ?? .init(fromPlay: false), actions: actions)
      }
      ResultNote(installer: installer, actions: actions)
    }
  }
}

// After an operation: what happened (a failure in the accent, with Show Log)
struct ResultNote: View {
  let installer: Installer
  let actions: PanelActions

  var body: some View {
    switch installer.phase {
    case .failed(_, let message):
      HStack(alignment: .top, spacing: 7) {
        LucideIcon(name: "triangle-alert", size: 13).foregroundStyle(Brand.accent).padding(.top, 1)
        VStack(alignment: .leading, spacing: 4) {
          Text(message).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg2).fixedSize(horizontal: false, vertical: true)
          Button("Show Log", action: actions.showLog).buttonStyle(QuietButtonStyle(color: Brand.accent))
            .font(.body(12.5, .bold)).bodyBox(12.5)
        }
      }
    // (an install that ends in Ready: existing game files; the downloads go on to waiting)
    case .succeeded(.uninstall, let message), .succeeded(.repair, let message), .succeeded(.install, let message):
      HStack(alignment: .top, spacing: 7) {
        LucideIcon(name: "circle-check", size: 13).foregroundStyle(Brand.good).padding(.top, 1)
        Text(message).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg2).fixedSize(horizontal: false, vertical: true)
      }
    default:
      EmptyView()
    }
  }
}

// Choose the install route: Steam, ArenaNet's installer (a dropped Gw2Setup-64.exe), or game files
// this Mac already has (another Wine app's install, cloned or copied). The chosen route's card
// opens; the others keep a single line.
struct ChoosePanel: View {
  @Bindable var installer: Installer
  let actions: PanelActions

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      InkHeading(title: "Install Guild Wars 2 from", size: 17, alignment: .center) { EmptyView() }
        .padding(.bottom, 2)
      RouteCard(selected: installer.route == .steam, icon: "store", title: "Steam", summary: "Valve's installer",
                detail: "Downloads Valve's Steam installer from Valve. You sign in and install the game in it.") {
        installer.route = .steam
      }
      RouteCard(selected: installer.route == .arenanet, icon: "download", title: "ArenaNet installer",
                summary: "Gw2Setup-64.exe",
                detail: "Get Gw2Setup-64.exe from the official site, then drop it below.") {
        installer.route = .arenanet
      } extra: {
        DropZone(installer: installer)
      }
      RouteCard(selected: installer.route == .existing, icon: "hard-drive", title: "Game files I already have",
                summary: "No download",
                detail: "From GW2 on Mac 0.1, CrossOver, Whisky or an app wrapper. No download.") {
        installer.route = .existing
      } extra: {
        ExistingGames(installer: installer)
      }
      Button(action: actions.install) {
        HStack(spacing: 10) {
          LucideIcon(name: "download", size: 18)
          Text("Install \(appName)")
        }
      }
      .buttonStyle(.crimson)
      .disabled(!installer.loaded || installer.isBusy)
      .padding(.top, 2)
      HStack(alignment: .top, spacing: 7) {
        LucideIcon(name: "info", size: 13).foregroundStyle(Brand.fg3)
        Text(installer.route == .existing
             ? "Cloned or copied into \(appName)'s bottle. The originals stay as they are."
             : "Every download comes from Valve or ArenaNet. \(appName) hosts nothing of the game.")
          .font(.body(12)).bodyBox(12, 1.3).foregroundStyle(Brand.fg3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .task {
      if installer.route == .existing && !installer.scanned { installer.scanGames() }
    }
  }
}

struct RouteCard<Extra: View>: View {
  let selected: Bool
  let icon: String
  let title: String
  // what an unselected card says on its single line
  let summary: String
  let detail: String
  let select: () -> Void
  @ViewBuilder var extra: Extra

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: select) {
        HStack(alignment: .top, spacing: 10) {
          ZStack {
            Circle().strokeBorder(selected ? Brand.accent : Brand.borderStrong, lineWidth: 1.5)
            if selected { Circle().fill(Brand.accent).frame(width: 8, height: 8) }
          }
          .frame(width: 16, height: 16)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              LucideIcon(name: icon, size: 15)
              Text(title).font(.body(14, .bold)).bodyBox(14)
              if !selected {
                Spacer(minLength: 8)
                Text(summary).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg3).lineLimit(1)
              }
            }
            .foregroundStyle(Brand.fg)
            if selected {
              Text(detail).font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg2)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(selected ? [.isSelected] : [])
      .accessibilityHint(selected ? "" : detail)
      if selected { extra }
    }
    .padding(.vertical, selected ? 11 : 9)
    .padding(.horizontal, 13)
    .background(selected ? Brand.bgRaised : .clear, in: .rect(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Brand.accent : Brand.border,
                                                             lineWidth: selected ? 1.5 : 1))
  }
}

extension RouteCard where Extra == EmptyView {
  init(selected: Bool, icon: String, title: String, summary: String, detail: String, select: @escaping () -> Void) {
    self.init(selected: selected, icon: icon, title: title, summary: summary, detail: detail, select: select) { EmptyView() }
  }
}

// Game files I already have: the Guild Wars 2 installs gw2om.sh scan found in other Wine apps
// (source, path, size, the route they imply), Choose folder… (or a dropped folder) for anything
// else, and whether the game's settings come along
struct ExistingGames: View {
  @Bindable var installer: Installer
  @State private var targeted = false
  static let rowHeight: CGFloat = 42

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      list
      if let problem = installer.folderProblem {
        HStack(alignment: .top, spacing: 6) {
          LucideIcon(name: "triangle-alert", size: 13).foregroundStyle(Brand.accent).padding(.top, 1)
          Text(problem).font(.body(12)).bodyBox(12, 1.3).foregroundStyle(Brand.accent)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 10) {
        Button(action: chooseFolder) {
          HStack(spacing: 5) {
            LucideIcon(name: "folder-open", size: 14)
            Text("Choose folder…").font(.body(12.5, .bold)).bodyBox(12.5)
          }
        }
        .buttonStyle(QuietButtonStyle(color: Brand.accent))
        .help("A Guild Wars 2 folder, or a bottle or app with one in it")
        Spacer(minLength: 4)
        InkCheckbox(title: "Also bring my game settings",
                    isOn: Binding(get: { installer.bringSettings && (installer.chosenGame?.hasSettings ?? false) },
                                  set: { installer.bringSettings = $0 }))
          .disabled(!(installer.chosenGame?.hasSettings ?? false))
          .help(installer.chosenGame?.hasSettings == false
                ? "There are no game settings next to these files"
                : "Your graphics options and the remembered login (GFXSettings.Gw2-64.exe.xml, Local.dat). The bottle's own are kept in a backup folder.")
      }
      if let game = installer.chosenGame {
        HStack(alignment: .top, spacing: 6) {
          LucideIcon(name: game.sameDisk ? "zap" : "hard-drive", size: 13).foregroundStyle(Brand.gold).padding(.top, 1)
          Text(game.sameDisk
               ? "Same disk: cloned in an instant, without taking extra space."
               : "Another disk: copied, \(Installer.gigabytes(game.bytes)) on this Mac's disk.")
            .font(.body(12)).bodyBox(12, 1.3).foregroundStyle(Brand.fg2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: \.isFileURL) else { return false }
      installer.choose(gameFolder: url)
      return true
    } isTargeted: { targeted = $0 }
  }

  @ViewBuilder private var list: some View {
    let games = installer.gameFolders
    if games.isEmpty {
      HStack(spacing: 8) {
        if installer.scanning {
          ProgressView().controlSize(.small)
          Text("Looking for Guild Wars 2 on this Mac…")
        } else {
          LucideIcon(name: "info", size: 14)
          Text("None found in GW2 on Mac 0.1, CrossOver, Whisky or app wrappers. Choose its folder below.")
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg3)
      .padding(.vertical, 9).padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(targeted ? Brand.accentSoft : Brand.surface, in: .rect(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Brand.accent : Brand.borderStrong, lineWidth: 1.2))
    } else {
      let rows = VStack(spacing: 0) {
        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
          if index > 0 { Rectangle().fill(Brand.border).frame(height: 1) }
          row(game)
        }
      }
      Group {
        // (a fixed height past three: the panel keeps its size)
        if games.count > 3 {
          ScrollView { rows }.scrollIndicators(.automatic).frame(height: Self.rowHeight * 3 + 2)
        } else {
          rows
        }
      }
      .background(Brand.bg, in: .rect(cornerRadius: 8))
      .clipShape(.rect(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Brand.accent : Brand.borderStrong, lineWidth: 1))
    }
  }

  private func row(_ game: Installer.GameFolder) -> some View {
    let selected = installer.chosenGame?.path == game.path
    return Button { installer.chosenGame = game; installer.folderProblem = nil } label: {
      HStack(spacing: 9) {
        ZStack {
          Circle().strokeBorder(selected ? Brand.accent : Brand.borderStrong, lineWidth: 1.3)
          if selected { Circle().fill(Brand.accent).frame(width: 6, height: 6) }
        }
        .frame(width: 13, height: 13)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(game.source).font(.body(13, .bold)).bodyBox(13).foregroundStyle(Brand.fg).lineLimit(1)
            RouteChip(route: game.route)
            Spacer(minLength: 4)
            Text(Installer.gigabytes(game.bytes)).font(.body(12, .semibold)).bodyBox(12).foregroundStyle(Brand.fg2)
          }
          Text(ExistingGames.shownPath(game.path)).font(.body(11.5)).bodyBox(11.5).foregroundStyle(Brand.fg3)
            .lineLimit(1).truncationMode(.middle)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: Self.rowHeight)
      .background(selected ? Brand.accentSoft : .clear)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help(game.path)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityLabel("\(game.source), \(game.route == .steam ? "Steam" : "ArenaNet"), \(Installer.gigabytes(game.bytes))")
  }

  // In a bottle, the game's Windows path ("C:\Program Files\Guild Wars 2"; the source names the
  // bottle); elsewhere the folder, with ~ for the home folder
  static func shownPath(_ path: String) -> String {
    if let r = path.range(of: "/drive_c/") {
      return "C:\\" + path[r.upperBound...].replacingOccurrences(of: "/", with: "\\")
    }
    let home = NSHomeDirectory()
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.folder, .application]
    panel.allowsMultipleSelection = false
    panel.message = "Choose the Guild Wars 2 folder (the one with Gw2-64.exe), or a bottle or app that has it"
    panel.prompt = "Use"
    if panel.runModal() == .OK, let url = panel.url { installer.choose(gameFolder: url) }
  }
}

// "Steam" or "ArenaNet": the route a found install implies
struct RouteChip: View {
  let route: Installer.Route
  var body: some View {
    Text(route == .steam ? "Steam" : "ArenaNet")
      .font(.body(10.5, .bold)).bodyBox(10.5)
      .tracking(0.3)
      .foregroundStyle(Brand.gold)
      .padding(.vertical, 1.5).padding(.horizontal, 5)
      .background(Brand.goldSoft, in: .rect(cornerRadius: 4))
      .fixedSize()
  }
}

// A small checkbox in the ink style (the accent when on)
struct InkCheckbox: View {
  let title: String
  @Binding var isOn: Bool
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button { isOn.toggle() } label: {
      HStack(spacing: 6) {
        ZStack {
          RoundedRectangle(cornerRadius: 3.5).fill(isOn ? Brand.accent : Brand.bg)
          RoundedRectangle(cornerRadius: 3.5).strokeBorder(isOn ? Brand.accent : Brand.borderStrong, lineWidth: 1.3)
          if isOn { LucideIcon(name: "check", size: 11).foregroundStyle(Brand.onAccent) }
        }
        .frame(width: 15, height: 15)
        Text(title).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg2).lineLimit(1)
      }
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(isOn ? "On" : "Off")
  }
}

// Drop Gw2Setup-64.exe here (or click to choose it); the link to ArenaNet's download page
struct DropZone: View {
  @Bindable var installer: Installer
  @State private var targeted = false
  static let officialDownload = URL(string: "https://www.guildwars2.com/en/download/")!

  var body: some View {
    HStack(spacing: 8) {
      switch installer.setupCheck {
      case .ok(let what):
        LucideIcon(name: "circle-check", size: 15).foregroundStyle(Brand.good)
        Text(what).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg2).lineLimit(1).truncationMode(.middle)
      case .bad(let why):
        LucideIcon(name: "triangle-alert", size: 15).foregroundStyle(Brand.accent)
        Text(why).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.accent).lineLimit(2)
      case .checking:
        ProgressView().controlSize(.small)
        Text("Checking Gw2Setup-64.exe…").font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg3)
      case nil:
        LucideIcon(name: "file-down", size: 15).foregroundStyle(Brand.fg3)
        Button("Drop Gw2Setup-64.exe here") { chooseFile() }
          .buttonStyle(QuietButtonStyle(color: Brand.fg3))
          .font(.body(12.5)).bodyBox(12.5)
      }
      Link(destination: DropZone.officialDownload) {
        Text("Official download ↗").font(.body(12.5, .bold)).bodyBox(12.5).foregroundStyle(Brand.accent)
      }
      .pointerStyle(.link)
      .help("ArenaNet's download page for Gw2Setup-64.exe")
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .background(targeted ? Brand.accentSoft : Brand.surface, in: .rect(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Brand.accent : Brand.borderStrong, lineWidth: 1.2))
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: \.isFileURL) else { return false }
      installer.choose(setup: url)
      return true
    } isTargeted: { targeted = $0 }
  }

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
    panel.message = "Choose Gw2Setup-64.exe, downloaded from ArenaNet's site"
    if panel.runModal() == .OK, let url = panel.url { installer.choose(setup: url) }
  }
}

// The install (or uninstall) as steps, with progress and Cancel
struct InstallingPanel: View {
  let installer: Installer
  let actions: PanelActions

  private var title: String {
    switch installer.operation {
    case .uninstall: return "Uninstalling"
    case .repair: return "Repairing"
    default:
      if installer.imported || installer.isOperating && installer.route == .existing { return "Installing from your files" }
      return (installer.installedRoute ?? installer.route) == .arenanet ? "Installing through ArenaNet" : "Installing through Steam"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      InkHeading(title: title, size: 17, alignment: .center) {
        if installer.operation != .uninstall {
          Button(installer.phase == .waitingForGame ? "Stop waiting" : "Cancel") { installer.cancel() }
            .buttonStyle(QuietButtonStyle(color: Brand.fg3))
            .font(.body(13, .semibold)).bodyBox(13)
            .help(installer.phase == .waitingForGame
                  ? "Stops following the game's download. The engine and the bottle stay; Install picks up from there."
                  : "Stops the install and removes what it set up so far")
        }
      }
      .padding(.bottom, 10)
      let steps = installer.steps
      ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
        StepRow(step: step, state: state(index), last: index == steps.count - 1,
                detail: detail(index, step), progress: index == installer.stepIndex ? installer.progress : nil)
      }
      if installer.phase == .waitingForGame {
        Text(installer.imported
             ? "Sign in to Steam: it brings your Guild Wars 2 up to date. This window follows it."
             : installer.installedRoute == .arenanet
             ? "Pick a folder in ArenaNet's installer and let it download. This window follows it."
             : "Sign in to Steam and install Guild Wars 2 there. This window follows the download.")
          .font(.body(12)).bodyBox(12).foregroundStyle(Brand.fg3).fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .brandPanel()
  }

  enum StepState { case done, current, todo }
  private func state(_ index: Int) -> StepState {
    guard let i = installer.stepIndex else { return .todo }
    return index < i ? .done : index == i ? .current : .todo
  }

  // The current step's detail shows what it downloads ("SteamSetup.exe · 2.1 of 3.4 MB")
  private func detail(_ index: Int, _ step: Installer.Step) -> String {
    guard index == installer.stepIndex, let p = installer.progress else { return step.detail }
    if p.total <= 0 { return p.done > 0 ? "\(p.label) · \(Installer.gigabytes(p.done)) so far" : step.detail }
    if p.total > 2_000_000_000 {
      return "\(p.label) · \(Installer.gigabytes(p.done)) of \(Installer.gigabytes(p.total))"
    }
    return "\(p.label) · \(Installer.megabytes(p.done)) of \(Installer.megabytes(p.total)) MB"
  }
}

struct StepRow: View {
  let step: Installer.Step
  let state: InstallingPanel.StepState
  let last: Bool
  let detail: String
  let progress: Installer.Progress?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        marker
        if !last {
          Rectangle().fill(state == .done ? Brand.accent : Brand.border).frame(width: 2)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(step.title)
          .font(.body(14, state == .todo ? .medium : .bold)).bodyBox(14)
          .foregroundStyle(state == .todo ? Brand.fg2 : Brand.fg)
        Text(detail).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg3).lineLimit(1).truncationMode(.middle)
        if let progress, progress.total > 0 {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Brand.surface)
              Capsule().fill(Brand.accent)
                .frame(width: geo.size.width * min(1, Double(progress.done) / Double(progress.total)))
            }
          }
          .frame(height: 5)
          .padding(.top, 2)
        }
      }
      .padding(.top, 2)
      .padding(.bottom, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityValue(state == .done ? "Done" : state == .current ? "In progress" : "Not started")
  }

  @ViewBuilder private var marker: some View {
    ZStack {
      switch state {
      case .done:
        Circle().fill(Brand.accent)
        LucideIcon(name: "check", size: 13).foregroundStyle(Brand.onAccent)
      case .current:
        Circle().fill(Brand.accentSoft)
        Circle().strokeBorder(Brand.accent, lineWidth: 1.5)
        Text("\(step.id)").font(.body(12, .bold)).bodyBox(12).foregroundStyle(Brand.accent)
      case .todo:
        Circle().strokeBorder(Brand.borderStrong, lineWidth: 1.5)
        Text("\(step.id)").font(.body(12, .bold)).bodyBox(12).foregroundStyle(Brand.fg3)
      }
    }
    .frame(width: 24, height: 24)
  }
}

// Ready: Play, and Repair, Settings, Uninstall…
struct ReadyPanel: View {
  let installer: Installer
  let actions: PanelActions

  // after an update of the app: an engine with the DXMT Settings asks for is this version's (Play
  // only brings the manifest along); anything else, an earlier build of my DXMT fork too, takes
  // Repair (or the next Play) to update
  private var versionChip: (warn: Bool, text: String) {
    guard installer.installedOtherVersion else { return (false, "Installed · \(installer.installedVersion)") }
    return installer.status["graphics"] == "yes"
      ? (false, "Installed · \(installer.appVersion)") : (true, "\(installer.installedVersion) · Repair to update")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InkHeading(title: "Ready", size: 17, alignment: .center) {
        PanelChip(pip: versionChip.warn ? Brand.warning : Brand.good, text: versionChip.text)
      }
      Button(action: actions.play) {
        HStack(spacing: 12) {
          LucideIcon(name: "play", size: 20)
          Text(installer.gameRunning ? "Guild Wars 2 is running" : "Play Guild Wars 2")
        }
      }
      .buttonStyle(.crimsonPlay)
      // (not while the watcher closes Steam after the game: Play starts it again once it's gone)
      .disabled(installer.launching || closing)
      .help(closing ? "Steam is closing after the game. Play again once it has." : "")
      SecondaryActions(installer: installer, actions: actions)
      Rectangle().fill(Brand.border).frame(height: 1)
      if closing {
        PanelTip(icon: "store", text: "Steam is closing…", spinning: true)
      } else {
        PanelTip(icon: installer.installedRoute == .arenanet ? "download" : "store",
                 text: installer.installedRoute == .arenanet
                   ? "Starts ArenaNet's launcher, then the game. Your login stays in it."
                   : "Starts Steam, then the game. After your first sign-in, Steam stays in the background.")
      }
      PanelTip(icon: "sparkles", text: "The first minutes on each map may hitch while shaders compile and FEX translates the game's code.")
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .brandPanel()
  }

  // after the game: the watcher closes the Steam the Play started (gw2om.sh watch-session)
  private var closing: Bool { installer.session?.closing ?? false }
}

// MARK: - Log

struct LogSheet: View {
  let installer: Installer
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InkHeading("Log", size: 17)
      ScrollView {
        Text(installer.log.joined(separator: "\n"))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(Brand.fg2)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(10)
      .background(Brand.bgRaised, in: .rect(cornerRadius: 8))
      HStack {
        Text("The full log is in ~/Library/Logs/\(appFolder).").font(.body(12)).bodyBox(12).foregroundStyle(Brand.fg3)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(18)
    .frame(width: 620, height: 420)
    .background(Brand.bg)
  }
}
