// The Settings window (the app menu > Settings…, ⌘,; the main window's Settings), as the design's
// "Settings — Performance" draws it: a parchment sidebar of panes with an ink accent, and the
// selected pane's settings in raised groups. Reads and changes the settings through
// Resources/gw2om.sh (`settings`, `set <key> <value>`), which keeps them in settings.conf and
// makes the game's environment from them at each start (gw2om.sh play). They take effect the next
// time the game starts.
//
// On this line some settings need pieces of mine that come in later steps. gw2om.sh settings says
// which (<key>_state=off:<reason>): their rows are greyed with the reason under them. A setting
// that works but is untested here has a note instead (<key>_note).

import AppKit
import SwiftUI

@MainActor @Observable
final class GameSettings {
  private(set) var values: [String: String] = [:]
  var error: String?
  var saving = false
  // Sparkle's automatic checks follow the "updates" setting (set by GW2onMacApp)
  var updates: Updates?
  // Troubleshooting's actions (reset the shader cache, reinstall the engine): running, and the
  // last one's answer
  var action: String?
  var actionResult: String?
  // arcdps (gw2om.sh set arcdps on|off): placing it means a download from deltaconnected.com, whose
  // progress the row shows; whether it is on comes from the game folder (arcdps, arcdps_state)
  var arcdpsWorking = false
  var arcdpsProgress: Installer.Progress?
  var arcdpsResult: String?
  private var arcdpsProcess: Process?
  private var arcdpsDone: String?
  private var arcdpsFailure: String?

  private let script = Brand.resources.appendingPathComponent("gw2om.sh")

  var loaded: Bool { !values.isEmpty }
  var installed: Bool { values["installed"] == "yes" }
  var running: Bool { values["running"] == "yes" }

  func reload() {
    // (the headless renders show made-up settings)
    guard ProcessInfo.processInfo.environment["GW2OM_RENDER"] == nil else { return }
    Task {
      let parsed = Installer.parseStatus(await Installer.capture(script: script, arguments: ["settings"]))
      values = parsed
      if let updates, let value = parsed["updates"], parsed["installed"] == "yes" {
        updates.automaticChecks = value == "on"
      }
    }
  }

  // For the renders: settings as gw2om.sh settings would print them
  func preview(_ values: [String: String]) { self.values = values }

  func toggle(_ key: String) -> Binding<Bool> {
    Binding(get: { self.values[key] == "on" }, set: { self.set(key, $0 ? "on" : "off") })
  }

  func choice(_ key: String, _ fallback: String) -> Binding<String> {
    Binding(get: { self.values[key] ?? fallback }, set: { self.set(key, $0) })
  }

  func set(_ key: String, _ value: String) {
    let previous = values[key]
    values[key] = value
    error = nil
    saving = true
    if key == "updates" { updates?.automaticChecks = value == "on" }
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["set", key, value])
      saving = false
      if !output.contains("@done ") {
        values[key] = previous
        if key == "updates" { updates?.automaticChecks = previous == "on" }
        error = output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "The setting could not be saved."
      }
      reload()
    }
  }

  // arcdps on or off, with gw2om.sh's lines as they come (its @progress while it downloads)
  func setArcdps(_ on: Bool) {
    guard !arcdpsWorking else { return }
    let previous = values["arcdps"]
    values["arcdps"] = on ? "on" : "off"
    arcdpsWorking = true
    arcdpsProgress = nil
    arcdpsResult = nil
    error = nil
    arcdpsDone = nil
    arcdpsFailure = nil
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "set", "arcdps", on ? "on" : "off"]
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let reader = LineReader { [weak self] line in
      Task { @MainActor in
        guard let self else { return }
        if line.hasPrefix("@progress ") {
          let parts = line.split(separator: " ")
          if parts.count >= 4, let d = Int64(parts[parts.count - 2]), let t = Int64(parts[parts.count - 1]) {
            self.arcdpsProgress = Installer.Progress(label: "arcdps", done: d, total: t)
          }
        } else if line.hasPrefix("@error ") {
          self.arcdpsFailure = String(line.dropFirst(7))
        } else if line.hasPrefix("@done ") {
          self.arcdpsDone = String(line.dropFirst(6))
        }
      }
    }
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty { handle.readabilityHandler = nil; reader.finish() } else { reader.feed(data) }
    }
    process.terminationHandler = { [weak self] _ in
      // (after the last lines: they are handled on the main actor in order)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        MainActor.assumeIsolated {
          guard let self else { return }
          self.arcdpsProcess = nil
          self.arcdpsWorking = false
          self.arcdpsProgress = nil
          if let done = self.arcdpsDone {
            self.arcdpsResult = done
          } else {
            self.values["arcdps"] = previous
            self.error = self.arcdpsFailure ?? "arcdps could not be turned \(on ? "on" : "off")."
          }
          self.reload()
        }
      }
    }
    do {
      try process.run()
      arcdpsProcess = process
    } catch {
      arcdpsWorking = false
      values["arcdps"] = previous
      self.error = "arcdps could not be turned \(on ? "on" : "off"): \(error.localizedDescription)"
    }
  }

  // gw2om.sh reset-shaders / reinstall-engine
  func run(_ command: String) {
    guard action == nil else { return }
    action = command
    actionResult = nil
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: [command])
      action = nil
      actionResult = output.split(separator: "\n").last { $0.hasPrefix("@done ") || $0.hasPrefix("@error ") }
        .map { String($0.drop { $0 != " " }.dropFirst()) } ?? "Done."
      reload()
    }
  }

  // Frame cap: DXMT's Metal-paced d3d11.preferredMaxFrameRate, a divisor of the display's refresh
  static let frameCaps: [(String, String)] = [
    ("off", "Off"), ("30", "30 fps"), ("40", "40 fps"), ("60", "60 fps"), ("120", "120 fps"),
  ]
  // Metal: the Metal my DXMT fork draws with (gw2om.sh metal: DXMT_METAL4 in the game's rule)
  static let metals: [(String, String)] = [("3", "Metal 3"), ("4", "Metal 4")]
  // CPUs the game sees: 2 up to this Mac's logical CPUs (gw2om.sh settings: cpus, sysctl
  // hw.logicalcpu), or all
  var cpuCount: Int { Int(values["cpus"] ?? "") ?? ProcessInfo.processInfo.processorCount }
  var cpuCounts: [(String, String)] {
    (2...max(2, cpuCount)).map { ("\($0)", "\($0)") } + [("all", "All")]
  }
  // Larger's interface scale with the addon (gw2-ui-scale.ini's scale; the nearest of the game's
  // own font sizes is used)
  static let interfaceScales: [(String, String)] = [
    ("1.5", "1.5×"), ("1.75", "1.67×"), ("1.8", "1.83×"), ("2.0", "2.06×"),
  ]
  // Mouse-look speed: a factor on the mouse's own counts from GameController (gw2om.sh MOUSE_SPEEDS)
  static let mouseSpeeds: [(String, String)] = ["0.5", "0.75", "1", "1.25", "1.5", "1.75", "2", "2.5", "3"]
    .map { ($0, $0 == "1" ? "1× (the mouse's own counts)" : "\($0)×") }
}

// The panes, in sidebar order
enum SettingsPane: String, CaseIterable, Identifiable {
  case graphics, performance, interface, game, mouse, updates, troubleshooting

  var id: Self { self }

  var title: String {
    switch self {
    case .graphics: "Graphics"
    case .performance: "Performance"
    case .interface: "Interface"
    case .game: "Game"
    case .mouse: "Mouse"
    case .updates: "Updates"
    case .troubleshooting: "Troubleshooting"
    }
  }

  var icon: String {
    switch self {
    case .graphics: "monitor"
    case .performance: "flame"
    case .interface: "type"
    case .game: "swords"
    case .mouse: "mouse"
    case .updates: "refresh-cw"
    case .troubleshooting: "stethoscope"
    }
  }

  // settings the game reads when it starts (Updates are Sparkle's, at once)
  var appliesAtNextGameStart: Bool { self != .updates }
}

struct SettingsView: View {
  static let designSize = CGSize(width: 780, height: 470)
  static let selectedPaneKey = "settingsPane"

  @Bindable var settings: GameSettings
  @AppStorage(Installer.quitAfterLaunchKey) private var quitAfterLaunch = false
  @AppStorage(Self.selectedPaneKey) private var selectedPane: SettingsPane = .graphics
  @State private var confirmInterface = false
  @State private var confirmArcdps = false
  @State private var confirmAction: String?
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(selectedPane.title)
            .font(.head(20))
            .foregroundStyle(Brand.fg)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.border).frame(height: 1) }
            .accessibilityAddTraits(.isHeader)
          pane(selectedPane)
            .disabled(!settings.loaded || !settings.installed)
          notes
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
      }
      .scrollBounceBehavior(.basedOnSize)
      // (no scroller column: it would narrow the rows; trackpads and wheels still scroll)
      .scrollIndicators(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background { SettingsBackground() }
    .ignoresSafeArea()
    .frame(minWidth: SettingsView.designSize.width, minHeight: SettingsView.designSize.height)
    .onAppear { settings.reload() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      settings.reload()
    }
    .sheet(isPresented: $confirmInterface) {
      InterfaceWarning(isPresented: $confirmInterface) { settings.set("uiscale", "on") }
    }
    .sheet(isPresented: $confirmArcdps) {
      ArcdpsWarning(isPresented: $confirmArcdps) { settings.setArcdps(true) }
    }
    .alert(confirmAction == "reset-shaders" ? "Reset the shader cache?" : "Reinstall the engine?",
           isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } })) {
      Button(confirmAction == "reset-shaders" ? "Reset" : "Reinstall", role: .destructive) {
        if let a = confirmAction { settings.run(a) }
        confirmAction = nil
      }
      Button("Cancel", role: .cancel) { confirmAction = nil }
    } message: {
      Text(confirmAction == "reset-shaders"
           ? "This clears \(appName)'s DXMT shader caches for the game (in ~/Library/Caches/\(appFolder)), my fork's and the engine's DXMT's: "
             + "its compiled shaders, pipeline archives and recorded pipelines. The next sessions build "
             + "them again, with more hitches at first."
           : "The Wine engine is unpacked again from the verified download and \(appName)'s graphics and "
             + "Wine pieces go back in. The bottle, the game and your settings stay.")
    }
  }

  // MARK: Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SettingsPane.allCases) { pane in
        let selected = pane == selectedPane
        Button { selectedPane = pane } label: {
          HStack(spacing: 10) {
            LucideIcon(name: pane.icon, size: 16).foregroundStyle(selected ? Brand.onAccent : Brand.accent)
            Text(pane.title).font(.body(14, selected ? .bold : .medium)).bodyBox(14)
              .foregroundStyle(selected ? Brand.onAccent : Brand.fg)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 7).padding(.horizontal, 10)
          .background(selected ? Brand.accent : .clear, in: .rect(cornerRadius: 7))
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
      }
      Spacer(minLength: 0)
      SidebarVersion()
    }
    .padding(.top, 44)
    .padding(.horizontal, 10)
    .padding(.bottom, 12)
    .frame(width: 214)
    .frame(maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .trailing) { Rectangle().fill(Brand.border).frame(width: 1) }
  }

  // MARK: Notes under the pane

  @ViewBuilder private var notes: some View {
    let notInstalled = settings.loaded && !settings.installed
    VStack(alignment: .leading, spacing: 8) {
      if let error = settings.error {
        note("triangle-alert", error, Brand.accent)
      } else if notInstalled {
        note("info", "Install \(appName) first.", Brand.fg3)
      }
      if selectedPane.appliesAtNextGameStart {
        note("info", "Changes take effect the next time the game starts.", Brand.fg3)
      }
    }
  }

  private func note(_ icon: String, _ text: String, _ color: Color) -> some View {
    HStack(alignment: .top, spacing: 7) {
      LucideIcon(name: icon, size: 13).padding(.top, 1)
      Text(text).font(.body(12.5)).bodyBox(12.5).fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(color)
  }

  // MARK: Panes

  // the reason a setting is off on this engine (gw2om.sh settings: <key>_state=off:<reason>)
  private func off(_ key: String) -> String? {
    guard let state = settings.values["\(key)_state"], state.hasPrefix("off:") else { return nil }
    return String(state.dropFirst(4))
  }

  // a setting that works but is untested on this engine (<key>_note)
  private func untested(_ key: String) -> String? {
    settings.values["\(key)_note"].flatMap { $0.isEmpty ? nil : $0 }
  }

  @ViewBuilder private func pane(_ pane: SettingsPane) -> some View {
    switch pane {
    case .graphics:
      SettingsGroup {
        SettingRow("Retina", "Draws the game at your display's full resolution (Wine's High Resolution Mode). Sharper, at some cost in frame rate.") {
          InkSwitch(isOn: settings.toggle("retina"))
        }
        SettingRow("Frame cap", "A steady cap paced by Metal, at a divisor of your display's refresh. Use it with the game's own vsync.") {
          InkPopup(selection: settings.choice("fpscap", "off"), options: GameSettings.frameCaps)
        }
      }
      SettingsGroup {
        SettingRow("Metal", "Metal 3 draws smoothly. Metal 4 is the newer path, and for now it stutters while the cursor moves.", off: off("metal")) {
          InkPopup(selection: settings.choice("metal", "3"), options: GameSettings.metals)
        }
        SettingRow("MetalFX for Subsample", "MetalFX upscales the 3D scene and the interface stays sharp. It works only with the game's Render Sampling set to Subsample, and does nothing at Native. Experimental.", off: off("metalfx")) {
          InkSwitch(isOn: settings.toggle("metalfx"))
        }
        SettingRow("Metal HUD", "Apple's overlay with the frame rate and frame times, over the game.") {
          InkSwitch(isOn: settings.toggle("hud"))
        }
        // (a switch of my Mac driver)
        SettingRow("Launcher frames", "The launcher's window gets a copy of each frame, and a frame equal to the last is skipped. Against a launcher that flickers.", off: off("launcherframes")) {
          InkSwitch(isOn: settings.toggle("launcherframes"))
        }
      }

    case .performance:
      SettingsGroup {
        SettingRow("Shader warming", "Builds the pipelines your last sessions used before the game asks for them: fewer hitches on busy maps. Up to 8,192, about 300 MB.", off: off("warm")) {
          InkSwitch(isOn: settings.toggle("warm"))
        }
        SettingRow("CPUs the game sees", "The game starts one job worker per CPU, minus one.") {
          InkPopup(selection: settings.choice("ncpu", "8"), options: settings.cpuCounts)
        }
      }
      // (the switches of my Wine build)
      SettingsGroup {
        SettingRow("Job wakes", "Each job the game hands out wakes one sleeping worker, and none when no worker sleeps. Without it, every hand-out wakes all of them.", off: off("jobwakes")) {
          InkSwitch(isOn: settings.toggle("jobwakes"))
        }
        SettingRow("Event pool", "The game creates and closes about 2,500 events a second. The pool reuses closed ones instead of asking the Wine server for each.", off: off("eventpool")) {
          InkSwitch(isOn: settings.toggle("eventpool"))
        }
        SettingRow("Faster locks", "Short waits before the game thread sleeps on a busy lock or job group.", off: off("fastlocks")) {
          InkSwitch(isOn: settings.toggle("fastlocks"))
        }
      }

    case .interface:
      SettingsGroup {
        SettingRow("Larger interface", interfaceDescription, note: untested("uiscale")) {
          InkSwitch(isOn: Binding(get: { settings.values["uiscale"] == "on" }, set: { on in
            if on { confirmInterface = true } else { settings.set("uiscale", "off") }
          }))
        }
        SettingRow("arcdps", arcdpsDescription, progress: arcdpsFraction, note: untested("arcdps")) {
          InkSwitch(isOn: Binding(get: { settings.values["arcdps"] == "on" }, set: { on in
            if on { confirmArcdps = true } else { settings.setArcdps(false) }
          }))
          .disabled(!arcdpsCanSwitch)
        }
      }
      if let state = settings.values["uiscale_addon"], state != "off", state != "on" {
        note("triangle-alert", interfaceStateNote(state), Brand.accent)
      }
      if let text = arcdpsStateNote {
        note("triangle-alert", text, Brand.accent)
      } else if let result = settings.arcdpsResult, !settings.arcdpsWorking {
        note("info", result, Brand.fg3)
      }
      SettingsGroup {
        SettingRow("Interface Size \"Larger\"", "How large the game's Larger size draws, from the game's own pre-rendered fonts.", note: untested("uiscale_size")) {
          InkPopup(selection: settings.choice("uiscale_size", "1.75"), options: GameSettings.interfaceScales)
        }
        SettingRow("Small text in Cronos", "Chat, the tracker and labels have no larger font of their own: draws them in the game's Cronos face at the larger size, sharp.", note: untested("uiscale_sans")) {
          InkSwitch(isOn: settings.toggle("uiscale_sans"))
        }
        SettingRow("Cinematic dialogue", "Story cinematics' dialogue sizes itself apart from the interface. Draws it at the same size as the rest (a small code patch).", note: untested("uiscale_cinema")) {
          InkSwitch(isOn: settings.toggle("uiscale_cinema"))
        }
      }
      .disabled(settings.values["uiscale"] != "on")

    case .game:
      SettingsGroup {
        SettingRow("Installed through", settings.values["route"] == "arenanet"
                   ? "ArenaNet's installer. Play starts the game's own launcher, Gw2-64.exe."
                   : "Steam. Play starts Steam, which starts the game (steam.exe -applaunch 1284210).") {
          Text(settings.values["route"] == "arenanet" ? "ArenaNet" : "Steam").font(.body(13, .semibold)).bodyBox(13).foregroundStyle(Brand.fg2)
        }
        SettingRow("Start Steam in the background", settings.values["route"] == "arenanet"
                   ? "For the Steam route only: this install starts the game's own launcher."
                   : "Once Steam remembers your login, Play starts it without its window and it starts the game. Until your first sign-in, Steam's window shows.") {
          InkSwitch(isOn: settings.toggle("steambg"))
            .disabled(settings.values["route"] == "arenanet")
        }
        if settings.values["route"] != "arenanet", settings.values["steambg"] == "on" {
          SettingRow("Quit Steam when the game quits", "When Play started Steam in the background, Steam quits by itself once Guild Wars 2 has quit. A Steam that was already running, or whose window showed, stays open.") {
            InkSwitch(isOn: settings.toggle("quitsteam"))
          }
        }
        // (on this line always on: every Wine process runs as the engine's loader, a Game Mode app)
        SettingRow("Game Mode", "While the game is in full screen, macOS gives it priority on the CPU and GPU and lowers the latency of Bluetooth controllers and headphones.", off: off("gamemode")) {
          InkSwitch(isOn: off("gamemode") == nil ? settings.toggle("gamemode") : .constant(true))
        }
      }
      SettingsGroup {
        SettingRow("Launch options", "Extra arguments for Gw2-64.exe, for example -maploadinfo.") {
          LaunchOptionsField(settings: settings)
        }
        SettingRow("Quit \(appName) after launching", "It doesn't need to stay open while you play.") {
          InkSwitch(isOn: $quitAfterLaunch)
        }
      }

    case .mouse:
      SettingsGroup {
        SettingRow("Raw mouse-look", "On, the game's raw mouse input is the mouse's own movement, read from GameController, without the pointer's acceleration. Off, it is the pointer's movement, as Wine usually does it. Takes effect the next time the game starts.", off: off("rawmouse")) {
          InkSwitch(isOn: settings.toggle("rawmouse"))
        }
        SettingRow("Mouse-look speed", "How fast the camera turns with raw mouse-look: a factor on the mouse's own counts, which the game gets at 1×. The game's own camera settings apply on top.", off: off("mousespeed")) {
          InkPopup(selection: settings.choice("mousespeed", "1"), options: GameSettings.mouseSpeeds)
        }
        .disabled(settings.values["rawmouse"] != "on")
      }

    case .updates:
      SettingsGroup {
        SettingRow("Check for updates automatically", settings.updates?.available == true
                   ? "\(appName) looks for a new version once a day. Updates install only when you choose to."
                   : "Not yet: \(appName) has no update feed so far. Check for Updates… turns on with the first public release.") {
          InkSwitch(isOn: settings.toggle("updates"))
            .disabled(settings.updates?.available != true)
        }
      }

    case .troubleshooting:
      SettingsGroup {
        SettingRow("Debug logging", "Detailed DXMT logs and Wine's errors, for bug reports, at some cost in performance. Turn it on only when asked to.") {
          InkSwitch(isOn: settings.toggle("debug"))
        }
      }
      SettingsGroup {
        SettingRow("Collect Logs", "A zip of \(appName)'s, Wine's, DXMT's and the game's logs for a bug report, without account names or passwords. Also in the \(appName) menu.") {
          SmallButton("Collect…", icon: "file-text") {
            NotificationCenter.default.post(name: .collectLogs, object: nil)
          }
        }
        SettingRow("Reset the shader cache", "Deletes DXMT's compiled shaders and recorded pipelines for the game. Try it if the game draws wrongly after an update.") {
          SmallButton(settings.action == "reset-shaders" ? "Resetting…" : "Reset…", icon: "eraser") {
            confirmAction = "reset-shaders"
          }
          .disabled(settings.action != nil || settings.running)
        }
        SettingRow("Reinstall the engine", "Unpacks the Wine engine again and puts \(appName)'s pieces back in. The bottle, the game and your settings stay.") {
          SmallButton(settings.action == "reinstall-engine" ? "Reinstalling…" : "Reinstall…", icon: "rotate-ccw") {
            confirmAction = "reinstall-engine"
          }
          .disabled(settings.action != nil || settings.running)
        }
      }
      if let result = settings.actionResult { note("info", result, Brand.fg3) }
      SettingsGroup {
        SettingRow("Get help", "Ask Pharaphobia on Discord or open a GitHub issue, with the zip from Collect Logs. Never ArenaNet's support: \(appName) is unofficial.") {
          HStack(spacing: 8) {
            Link(destination: Support.discord) { Text("Discord ↗").font(.body(13, .bold)).foregroundStyle(Brand.accent) }
            Link(destination: Support.issues) { Text("GitHub ↗").font(.body(13, .bold)).foregroundStyle(Brand.accent) }
          }
          .fixedSize()
        }
      }
    }
  }

  private var interfaceDescription: String {
    "Makes Interface Size \"Larger\" larger and sharp at 4K, from the game's own fonts. An addon "
      + "(version.dll) that changes the game's memory, which ArenaNet doesn't support."
  }

  // arcdps: what it is, or the download while it runs
  private var arcdpsDescription: String {
    if settings.arcdpsWorking {
      if settings.values["arcdps"] != "on" { return "Removing arcdps from the game folder…" }
      guard let p = settings.arcdpsProgress, p.total > 0 else { return "Downloading arcdps from deltaconnected.com…" }
      return "Downloading arcdps from deltaconnected.com… \(Installer.megabytes(p.done)) of \(Installer.megabytes(p.total)) MB"
    }
    return "deltaconnected's addon (d3d11.dll), downloaded from deltaconnected.com; it updates itself. "
      + "It reads the game's memory, which ArenaNet doesn't support."
  }

  private var arcdpsFraction: Double? {
    guard settings.arcdpsWorking else { return nil }
    guard let p = settings.arcdpsProgress, p.total > 0 else { return 0 }
    return min(1, Double(p.done) / Double(p.total))
  }

  // on: always (it can be removed); off: only into an empty place, with the game installed and closed
  private var arcdpsCanSwitch: Bool {
    guard !settings.arcdpsWorking, !settings.running else { return false }
    if settings.values["arcdps"] == "on" { return true }
    return settings.values["arcdps_state"] == "off"
  }

  private var arcdpsStateNote: String? {
    if settings.arcdpsWorking { return nil }
    let foreign = settings.values["arcdps_foreign"].flatMap { $0.isEmpty ? nil : $0 } ?? "d3d11.dll"
    switch settings.values["arcdps_state"] {
    case "foreign":
      return "The game folder has another \(foreign.replacingOccurrences(of: " ", with: " and ")) (Nexus or another addon?). \(appName) leaves it alone, so it doesn't add arcdps."
    case "nogame":
      return "The game is not installed yet: arcdps can go in once it is."
    default:
      return settings.running && settings.loaded ? "Quit the game and Steam to turn arcdps on or off." : nil
    }
  }

  private func interfaceStateNote(_ state: String) -> String {
    switch state {
    case "foreign": return "The game folder has another version.dll (another addon?). \(appName) leaves it alone, so the larger interface is off."
    case "missing": return "The addon is not in the game folder (a game update or repair may have removed it). Turn it off and on again."
    case "nogame": return "The game is not installed yet: the addon goes in when it is."
    default: return state
    }
  }
}

// The window's background: the parchment, the sidebar's surface and, as in the design, a faint
// ink stroke near the sidebar's foot that runs on under the panes (the header's stroke, multiplied
// at 22%; lightened in dark)
struct SettingsBackground: View {
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    ZStack(alignment: .topLeading) {
      Brand.bg
      Brand.surface.frame(width: 214)
      ArtImage(name: scheme == .dark ? "header-dark.png" : "header-light.png")
        .frame(width: 300, height: 150)
        .clipped()
        .opacity(scheme == .dark ? 0.35 : 0.22)
        .rotationEffect(.degrees(8))
        .offset(x: -40, y: 330)
        .blendMode(scheme == .dark ? .lighten : .multiply)
    }
    .compositingGroup()
    .clipped()
  }
}

extension Notification.Name {
  static let collectLogs = Notification.Name("GW2onMacCollectLogs")
}

// The warning before the larger interface goes in (my rule: off by default, a clear warning,
// installed only after the user confirms)
struct InterfaceWarning: View {
  @Binding var isPresented: Bool
  let confirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        LucideIcon(name: "triangle-alert", size: 22).foregroundStyle(Brand.accent)
        Text("Turn on the larger interface?").font(.head(19)).foregroundStyle(Brand.fg)
      }
      VStack(alignment: .leading, spacing: 8) {
        bullet("It changes the game's memory while it runs: the font table, and one piece of the game's code (a small patch so story cinematics' dialogue draws at the same size).")
        bullet("ArenaNet doesn't support addons that do this. Use it at your own risk.")
        bullet("It may stop working after a game update. Then turn it off here.")
        bullet("It installs version.dll and gw2-ui-scale.ini into the game folder. Turning it off removes both.")
      }
      HStack {
        Spacer()
        Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
        Button("Turn On") { isPresented = false; confirm() }.keyboardShortcut(.defaultAction).tint(Brand.accent)
      }
    }
    .padding(22)
    .frame(width: 460)
    .background(Brand.bg)
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Circle().fill(Brand.accent).frame(width: 5, height: 5).padding(.top, 6)
      Text(text).font(.body(13)).bodyBox(13).foregroundStyle(Brand.fg2).fixedSize(horizontal: false, vertical: true)
    }
  }
}

// The warning before arcdps goes in (as the larger interface's: off by default, a clear warning,
// installed only after the user confirms)
struct ArcdpsWarning: View {
  @Binding var isPresented: Bool
  let confirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        LucideIcon(name: "triangle-alert", size: 22).foregroundStyle(Brand.accent)
        Text("Turn on arcdps?").font(.head(19)).foregroundStyle(Brand.fg)
      }
      VStack(alignment: .leading, spacing: 8) {
        bullet("arcdps is a third-party addon by deltaconnected. It is not made or supported by ArenaNet, NCSOFT or \(appName).")
        bullet("It reads the game's memory while it runs. Use it at your own risk: there is no help or warranty for it from \(appName).")
        bullet("\(appName) downloads it from deltaconnected.com and puts it into the game folder as d3d11.dll. From then on arcdps updates itself.")
        bullet("Turning it off removes d3d11.dll and keeps arcdps's settings (addons/arcdps).")
      }
      HStack {
        Spacer()
        Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
        Button("Download and Turn On") { isPresented = false; confirm() }.keyboardShortcut(.defaultAction).tint(Brand.accent)
      }
    }
    .padding(22)
    .frame(width: 460)
    .background(Brand.bg)
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Circle().fill(Brand.accent).frame(width: 5, height: 5).padding(.top, 6)
      Text(text).font(.body(13)).bodyBox(13).foregroundStyle(Brand.fg2).fixedSize(horizontal: false, vertical: true)
    }
  }
}

// A raised group of settings rows (the design's "Group")
struct SettingsGroup<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          row
          if index < rows.count - 1 { Rectangle().fill(Brand.border).frame(height: 1) }
        }
      }
    }
    .brandPanel()
  }
}

// One setting: its title and description on the left, the control on the right
struct SettingRow<Control: View>: View {
  let title: String
  let detail: String
  // a bar under the detail while something runs (0 to 1), as the install's steps draw theirs
  var progress: Double?
  // why the setting is off on this engine: the control is greyed and this shows under the detail
  var off: String?
  // a warning that shows under the detail, the control staying as it is (untested on this engine)
  var note: String?
  @ViewBuilder var control: Control

  init(_ title: String, _ detail: String, progress: Double? = nil, off: String? = nil, note: String? = nil,
       @ViewBuilder control: () -> Control) {
    self.title = title
    self.detail = detail
    self.progress = progress
    self.off = off
    self.note = note
    self.control = control()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body(14, .bold)).bodyBox(14).foregroundStyle(Brand.fg)
        Text(detail).font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg2)
          .fixedSize(horizontal: false, vertical: true)
        if let line = off ?? note {
          HStack(alignment: .top, spacing: 6) {
            LucideIcon(name: off != nil ? "info" : "triangle-alert", size: 12).padding(.top, 1)
            Text(line).font(.body(12.5, .semibold)).bodyBox(12.5, 1.3).fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(off != nil ? Brand.fg3 : Brand.accent)
          .padding(.top, 3)
        }
        if let progress {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Brand.surface)
              Capsule().fill(Brand.accent).frame(width: geo.size.width * progress)
            }
          }
          .frame(height: 5)
          .padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      control.labelsHidden().accessibilityLabel(Text(title)).disabled(off != nil)
    }
    .padding(.vertical, 11)
    .padding(.horizontal, 14)
    .accessibilityElement(children: .contain)
  }
}

struct SmallButton: View {
  let title: String
  let icon: String
  let action: () -> Void
  init(_ title: String, icon: String, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        LucideIcon(name: icon, size: 13)
        Text(title).font(.body(13, .semibold)).bodyBox(13)
      }
      .foregroundStyle(Brand.fg)
      .padding(.vertical, 4).padding(.horizontal, 10)
      .background(Brand.bg, in: .rect(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.borderStrong, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .fixedSize()
  }
}

// Launch options: saved when the field is submitted or loses focus
struct LaunchOptionsField: View {
  let settings: GameSettings
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text, prompt: Text("none"))
      .textFieldStyle(.plain)
      .font(.body(13)).bodyBox(13)
      .padding(.vertical, 4).padding(.horizontal, 8)
      .frame(width: 170)
      .background(Brand.bg, in: .rect(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.borderStrong, lineWidth: 1))
      .focused($focused)
      .onAppear { text = settings.values["launchopts"] ?? "" }
      .onChange(of: settings.values["launchopts"]) { _, new in if !focused { text = new ?? "" } }
      .onSubmit(save)
      .onChange(of: focused) { _, now in if !now { save() } }
  }

  private func save() {
    if text != (settings.values["launchopts"] ?? "") { settings.set("launchopts", text) }
  }
}

// The foot of the sidebar: the versions (selectable, for bug reports)
struct SidebarVersion: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }
  var body: some View {
    let parts = [version.isEmpty ? "" : "\(appName) \(version)",
                 AppActions.componentVersions().components(separatedBy: " · ").first ?? ""].filter { !$0.isEmpty }
    Text(parts.joined(separator: " · "))
      .font(.body(11)).bodyBox(11)
      .foregroundStyle(Brand.fg3)
      .textSelection(.enabled)
      .lineLimit(1)
      .padding(.horizontal, 10)
  }
}
