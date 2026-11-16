// The Settings window (GW2 on Mac > Settings…, ⌘,; the main window's Settings), as the design's
// "Settings — Performance" draws it: a parchment sidebar of panes with an ink accent, and the
// selected pane's settings in raised groups. Reads and changes the settings through
// Resources/gw2om.sh (`settings`, `set <key> <value>`), which keeps them in settings.conf and
// makes the game's environment from them at each start (gw2om.sh play). They take effect the next
// time the game starts.
//
// Mouse is SWTOR on Mac's raw mouse-look: an option of the app's build of Wine's Mac driver, which
// gw2om.sh turns on for Gw2-64.exe in the bottle's registry (only while no session runs, like
// Retina). The driver also has SWTOR on Mac's game keys by keyboard position; there is no Keyboard
// pane, and nothing turns it on.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
  // arcdps and ReShade (gw2om.sh set arcdps|reshade on|off): placing one means downloads, whose
  // progress its row shows. Whether arcdps is on comes from the game folder (arcdps,
  // arcdps_state); for ReShade, reshade is the player's wish and reshade_state the game folder.
  struct AddonJob {
    var working = false
    var progress: Installer.Progress?
    var result: String?
    fileprivate var process: Process?
    fileprivate var done: String?
    fileprivate var failure: String?
  }
  var arcdps = AddonJob()
  var reshade = AddonJob()
  // (both take the session's lock: while one works, the other would be refused)
  var addonWorking: Bool { arcdps.working || reshade.working }
  // ReShade's presets and shaders (gw2om.sh reshade import): running; the report, which takes the
  // place of ReShade's last @done under the group; the one preset that came in, for "Use this
  // preset now?"
  var reshadeImporting = false
  var reshadeReport: String?
  var importedPreset: String?

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

  func setArcdps(_ on: Bool) { setAddon(\.arcdps, key: "arcdps", name: "arcdps", on) }
  func setReshade(_ on: Bool) {
    reshadeReport = nil
    setAddon(\.reshade, key: "reshade", name: "ReShade", on)
  }

  // Files and folders into the ReShade folder: the report as gw2om.sh gives it (it lists a few
  // missing effects, the output and the log all of them), and the question for a single preset
  // while the game is closed (reshade use refuses while it runs)
  func importReshade(_ urls: [URL]) {
    let paths = urls.filter(\.isFileURL).map(\.path)
    guard !reshadeImporting, !reshade.working, !paths.isEmpty else { return }
    reshadeImporting = true
    error = nil
    let script = script
    Task {
      let lines = await Installer.capture(script: script, arguments: ["reshade", "import"] + paths)
        .split(separator: "\n").map(String.init)
      reshadeImporting = false
      if let done = lines.last(where: { $0.hasPrefix("@done ") }) {
        reshade.result = nil
        reshadeReport = String(done.dropFirst(6))
        let presets = lines.filter { $0.hasPrefix("@preset ") }.map { String($0.dropFirst(8)) }
        if presets.count == 1, !running { importedPreset = presets[0] }
      } else {
        error = lines.first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) } ?? "The presets and shaders could not be added."
      }
      reload()
    }
  }

  // A preset that came in as ReShade's current one (gw2om.sh reshade use): its answer goes after
  // the import's report
  func usePreset(_ name: String) {
    let script = script
    Task {
      let lines = await Installer.capture(script: script, arguments: ["reshade", "use", name]).split(separator: "\n")
      if let done = lines.last(where: { $0.hasPrefix("@done ") }) {
        reshadeReport = [reshadeReport, String(done.dropFirst(6))].compactMap { $0 }.joined(separator: " ")
      } else {
        error = lines.first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) } ?? "\(name) could not be made ReShade's preset."
      }
    }
  }

  // An addon on or off, with gw2om.sh's lines as they come (its @progress while it downloads).
  // Without its @done the switch goes back.
  private func setAddon(_ job: ReferenceWritableKeyPath<GameSettings, AddonJob>, key: String, name: String, _ on: Bool) {
    guard !addonWorking else { return }
    let previous = values[key]
    values[key] = on ? "on" : "off"
    self[keyPath: job] = AddonJob(working: true)
    error = nil
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "set", key, on ? "on" : "off"]
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let reader = LineReader { [weak self] line in
      Task { @MainActor in
        guard let self else { return }
        if line.hasPrefix("@progress ") {
          // (@progress <label, maybe with spaces> <bytes> <total>)
          let parts = line.split(separator: " ")
          if parts.count >= 4, let d = Int64(parts[parts.count - 2]), let t = Int64(parts[parts.count - 1]) {
            let label = parts[1..<(parts.count - 2)].joined(separator: " ")
            self[keyPath: job].progress = Installer.Progress(label: label, done: d, total: t)
          }
        } else if line.hasPrefix("@error ") {
          self[keyPath: job].failure = String(line.dropFirst(7))
        } else if line.hasPrefix("@done ") {
          self[keyPath: job].done = String(line.dropFirst(6))
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
          let finished = self[keyPath: job]
          self[keyPath: job] = AddonJob(result: finished.done)
          if finished.done == nil {
            self.values[key] = previous
            self.error = finished.failure ?? "\(name) could not be turned \(on ? "on" : "off")."
          }
          self.reload()
        }
      }
    }
    do {
      try process.run()
      self[keyPath: job].process = process
    } catch {
      self[keyPath: job] = AddonJob()
      values[key] = previous
      self.error = "\(name) could not be turned \(on ? "on" : "off"): \(error.localizedDescription)"
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
  // Mouse-look speed: a factor on the macOS pointer's speed (gw2om.sh MOUSE_SPEEDS)
  static let mouseSpeeds: [(String, String)] = ["0.5", "0.75", "1", "1.25", "1.5", "1.75", "2", "2.5", "3"]
    .map { ($0, $0 == "1" ? "1× (pointer speed)" : "\($0)×") }
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
  @State private var confirmReshade = false
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
    // (presets, zips and folders dropped anywhere on the window: into the ReShade folder, and the
    // pane whose row shows the report)
    .dropDestination(for: URL.self) { urls, _ in
      guard settings.installed, !settings.reshadeImporting, !settings.reshade.working, urls.contains(where: \.isFileURL) else { return false }
      selectedPane = .interface
      settings.importReshade(urls)
      return true
    }
    .onAppear { settings.reload() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      settings.reload()
    }
    .sheet(isPresented: $confirmInterface) {
      InterfaceWarning(isPresented: $confirmInterface) { settings.set("uiscale", "on") }
    }
    .sheet(isPresented: $confirmArcdps) {
      AddonWarning.arcdps(isPresented: $confirmArcdps) { settings.setArcdps(true) }
    }
    .sheet(isPresented: $confirmReshade) {
      AddonWarning.reshade(isPresented: $confirmReshade, version: settings.values["reshade_version"]) {
        settings.setReshade(true)
      }
    }
    .sheet(isPresented: Binding(get: { settings.importedPreset != nil }, set: { if !$0 { settings.importedPreset = nil } })) {
      let name = settings.importedPreset ?? ""
      AddonWarning.preset(isPresented: Binding(get: { settings.importedPreset != nil }, set: { if !$0 { settings.importedPreset = nil } }),
                          name: name) { settings.usePreset(name) }
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
           ? "This clears GW2 on Mac's DXMT shader cache for the game (in ~/Library/Caches/GW2 on Mac/dxmt): "
             + "its compiled shaders, pipeline archives and recorded pipelines. The next sessions build "
             + "them again, with more hitches at first."
           : "The Wine engine is unpacked again from the verified download and GW2 on Mac's graphics and "
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
        note("info", "Install GW2 on Mac first.", Brand.fg3)
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

  private var workers: Int {
    let n = settings.values["ncpu"] ?? "8"
    return max(1, (Int(n) ?? ProcessInfo.processInfo.activeProcessorCount) - 1)
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
        SettingRow("MetalFX for Subsample", "With the game's Render Sampling set to Subsample, MetalFX upscales the 3D scene and the interface stays sharp. Experimental.") {
          InkSwitch(isOn: settings.toggle("metalfx"))
        }
        SettingRow("Metal HUD", "Apple's overlay with the frame rate and frame times, over the game.") {
          InkSwitch(isOn: settings.toggle("hud"))
        }
      }

    case .performance:
      SettingsGroup {
        SettingRow("Shader warming", "Builds the pipelines your last sessions used before the game asks for them: fewer hitches on busy maps. Up to 8,192, about 300 MB.") {
          InkSwitch(isOn: settings.toggle("warm"))
        }
        SettingRow("Cooler job workers", "Moves some of the game's job workers to the efficiency cores. Saves power; all of them can cost frames in big crowds.") {
          InkPopup(selection: settings.choice("coolworkers", "off"),
                   options: [("off", "Off")] + (1...workers).map { ("\($0)", "\($0) of \(workers)") })
        }
      }
      SettingsGroup {
        SettingRow("Faster locks", "Short waits before the game thread sleeps on a busy lock or job group.") {
          InkSwitch(isOn: settings.toggle("fastlocks"))
        }
        SettingRow("CPUs the game sees", "The game starts one job worker per CPU, minus one.") {
          InkPopup(selection: settings.choice("ncpu", "8"), options: settings.cpuCounts)
        }
      }

    case .interface:
      SettingsGroup {
        SettingRow("Larger interface", interfaceDescription) {
          InkSwitch(isOn: Binding(get: { settings.values["uiscale"] == "on" }, set: { on in
            if on { confirmInterface = true } else { settings.set("uiscale", "off") }
          }))
        }
        SettingRow("arcdps", arcdpsDescription, progress: addonFraction(settings.arcdps)) {
          InkSwitch(isOn: Binding(get: { settings.values["arcdps"] == "on" }, set: { on in
            if on { confirmArcdps = true } else { settings.setArcdps(false) }
          }))
          .disabled(!arcdpsCanSwitch)
        }
        SettingRow("ReShade", reshadeDescription, progress: addonFraction(settings.reshade)) {
          InkSwitch(isOn: Binding(get: { settings.values["reshade"] == "on" }, set: { on in
            if on { confirmReshade = true } else { settings.setReshade(false) }
          }))
          .disabled(!reshadeCanSwitch)
        } buttons: {
          if let folder = reshadeFolder {
            SmallButton("Open ReShade folder", icon: "folder-open") { NSWorkspace.shared.open(folder) }
          }
          SmallButton(settings.reshadeImporting ? "Adding…" : "Add preset or shaders…", icon: "file-down") { chooseReshadeFiles() }
            .disabled(settings.reshadeImporting || settings.reshade.working)
        }
      }
      if let state = settings.values["uiscale_state"], state != "off", state != "on" {
        note("triangle-alert", interfaceStateNote(state), Brand.accent)
      }
      if let text = otherAddonNote(arcdps: true) {
        note("info", text, Brand.fg3)
      } else if let text = arcdpsStateNote {
        note("triangle-alert", text, Brand.accent)
      } else if let result = settings.arcdps.result, !settings.arcdps.working {
        note("info", result, Brand.fg3)
      }
      if let text = otherAddonNote(arcdps: false) {
        note("info", text, Brand.fg3)
      } else if let text = reshadeStateNote {
        note("triangle-alert", text, Brand.accent)
      } else if let result = settings.reshade.result, !settings.reshade.working {
        note("info", result, Brand.fg3)
      }
      if let report = settings.reshadeReport, !settings.reshade.working {
        note("info", report, Brand.fg3)
      }
      SettingsGroup {
        SettingRow("Interface Size \"Larger\"", "How large the game's Larger size draws, from the game's own pre-rendered fonts.") {
          InkPopup(selection: settings.choice("uiscale_size", "1.75"), options: GameSettings.interfaceScales)
        }
        SettingRow("Small text in Cronos", "Chat, the tracker and labels have no larger font of their own: draws them in the game's Cronos face at the larger size, sharp.") {
          InkSwitch(isOn: settings.toggle("uiscale_sans"))
        }
        SettingRow("Cinematic dialogue", "Story cinematics' dialogue sizes itself apart from the interface. Draws it at the same size as the rest (a small code patch).") {
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
        SettingRow("Game Mode", "While the game is in full screen, macOS gives it priority on the CPU and GPU and lowers the latency of Bluetooth controllers and headphones.") {
          InkSwitch(isOn: settings.toggle("gamemode"))
        }
      }
      SettingsGroup {
        SettingRow("Launch options", "Extra arguments for Gw2-64.exe, for example -maploadinfo.") {
          LaunchOptionsField(settings: settings)
        }
        SettingRow("Quit GW2 on Mac after launching", "It doesn't need to stay open while you play.") {
          InkSwitch(isOn: $quitAfterLaunch)
        }
      }

    case .mouse:
      SettingsGroup {
        SettingRow("Raw mouse-look", "While you hold a mouse button to turn the camera, the game gets every movement straight from the mouse as it happens, not once per screen refresh, and the pointer stays put. Turn it off for Wine's usual mouse-look.") {
          InkSwitch(isOn: settings.toggle("rawmouse"))
        }
        SettingRow("Mouse-look speed", "How fast the camera turns with raw mouse-look, compared with your pointer speed in System Settings. The game's own camera settings apply on top.") {
          InkPopup(selection: settings.choice("mousespeed", "1"), options: GameSettings.mouseSpeeds)
        }
        .disabled(settings.values["rawmouse"] != "on")
      }

    case .updates:
      SettingsGroup {
        SettingRow("Check for updates automatically", settings.updates?.available == true
                   ? "GW2 on Mac looks for a new version once a day. Updates install only when you choose to."
                   : "Not yet: GW2 on Mac has no update feed so far. Check for Updates… turns on with the first public release.") {
          InkSwitch(isOn: settings.toggle("updates"))
            .disabled(settings.updates?.available != true)
        }
      }

    case .troubleshooting:
      SettingsGroup {
        SettingRow("Debug logging", "Detailed DXMT and Wine logs and the heat counters, for bug reports, at some cost in performance. Turn it on only when asked to.") {
          InkSwitch(isOn: settings.toggle("debug"))
        }
      }
      SettingsGroup {
        SettingRow("Collect Logs", "A zip of GW2 on Mac's, Wine's, DXMT's and the game's logs for a bug report, without account names or passwords. Also in the GW2 on Mac menu.") {
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
        SettingRow("Reinstall the engine", "Unpacks the Wine engine again and puts GW2 on Mac's pieces back in. The bottle, the game and your settings stay.") {
          SmallButton(settings.action == "reinstall-engine" ? "Reinstalling…" : "Reinstall…", icon: "rotate-ccw") {
            confirmAction = "reinstall-engine"
          }
          .disabled(settings.action != nil || settings.running)
        }
      }
      if let result = settings.actionResult { note("info", result, Brand.fg3) }
      SettingsGroup {
        SettingRow("Get help", "Ask Pharaphobia on Discord or open a GitHub issue, with the zip from Collect Logs. Never ArenaNet's support: GW2 on Mac is unofficial.") {
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
    if settings.arcdps.working {
      if settings.values["arcdps"] != "on" { return "Removing arcdps from the game folder…" }
      guard let p = settings.arcdps.progress, p.total > 0 else { return "Downloading arcdps from deltaconnected.com…" }
      return "Downloading arcdps from deltaconnected.com… \(Installer.megabytes(p.done)) of \(Installer.megabytes(p.total)) MB"
    }
    return "deltaconnected's addon, downloaded from deltaconnected.com; it updates itself. "
      + "It reads the game's memory, which ArenaNet doesn't support."
  }

  private func addonFraction(_ job: GameSettings.AddonJob) -> Double? {
    guard job.working else { return nil }
    guard let p = job.progress, p.total > 0 else { return 0 }
    return min(1, Double(p.done) / Double(p.total))
  }

  // on: always (it can be removed); off: only into an empty place, with the game installed and closed
  private var arcdpsCanSwitch: Bool {
    guard !settings.addonWorking, !settings.running else { return false }
    if settings.values["arcdps"] == "on" { return true }
    return settings.values["arcdps_state"] == "off"
  }

  private var arcdpsStateNote: String? {
    if settings.arcdps.working { return nil }
    let foreign = names(settings.values["arcdps_foreign"]) ?? "d3d11.dll"
    switch settings.values["arcdps_state"] {
    case "foreign":
      switch settings.values["reshade_state"] {
      case "foreign": return "The game folder has a ReShade that GW2 on Mac didn't put there (\(foreign)). GW2 on Mac leaves it alone, so it doesn't add arcdps."
      default: return "The game folder has another \(foreign) (Nexus or another addon?). GW2 on Mac leaves it alone, so it doesn't add arcdps."
      }
    case "nogame":
      return "The game is not installed yet: arcdps can go in once it is."
    default:
      return settings.running && settings.loaded ? "Quit the game and Steam to turn arcdps on or off." : nil
    }
  }

  // In the exclusive layout (gw2om.sh's ADDONS_LAYOUT) each addon's switch waits until the other is
  // off: a normal state, so a calm note (gw2om.sh's refusal names the other). In the together
  // layout they share the game folder, and a file in the way is another program's.
  private func otherAddonNote(arcdps: Bool) -> String? {
    guard settings.values["addons_layout"] == "exclusive" else { return nil }
    if arcdps, !settings.arcdps.working, settings.values["arcdps_state"] == "foreign", settings.values["reshade_state"] == "on" {
      let dll = names(settings.values["reshade_dll"]) ?? "d3d11.dll"
      return "ReShade is in the game folder as \(dll). Turn ReShade off first, then turn arcdps on."
    }
    if !arcdps, !settings.reshade.working, settings.values["reshade_state"] == "blocked", settings.values["arcdps_state"] == "on" {
      let dll = names(settings.values["reshade_blocker"]) ?? "d3d11.dll"
      return "arcdps is in the game folder as \(dll). Turn arcdps off first, then turn ReShade on."
    }
    return nil
  }

  // gw2om.sh's space-separated file names ("d3d11.dll dxgi.dll") as a sentence's, or nil for none
  private func names(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value.replacingOccurrences(of: " ", with: " and ")
  }

  // ReShade: what it is, or the download while it runs (gw2om.sh's @progress labels: ReShade's
  // installer from reshade.me; the compiler and the two effect packs from GitHub)
  private var reshadeDescription: String {
    if settings.reshade.working {
      if settings.values["reshade"] != "on" { return "Removing ReShade from the game folder…" }
      guard let p = settings.reshade.progress else { return "Downloading ReShade from reshade.me…" }
      let what = "Downloading \(p.label) from \(p.label == "ReShade" ? "reshade.me" : "GitHub")…"
      return p.total > 0 ? "\(what) \(Installer.megabytes(p.done)) of \(Installer.megabytes(p.total)) MB" : what
    }
    let version = settings.values["reshade_version"].flatMap { $0.isEmpty ? nil : " " + $0 } ?? ""
    return "Post-processing effects by crosire, drawn over the finished picture. Downloads ReShade\(version) "
      + "from reshade.me. Open its menu in the game with the Home key (fn + Left Arrow on a MacBook)."
  }

  // As gw2om.sh refuses: off goes whenever the player's wish is on (it leaves another ReShade or
  // another program's file alone); on only into an empty place, with the game installed and
  // closed. Disabled in foreign, blocked and nogame unless the wish is still on.
  private var reshadeCanSwitch: Bool {
    guard !settings.addonWorking, !settings.running else { return false }
    let state = settings.values["reshade_state"]
    if settings.values["reshade"] == "on" { return state != "nogame" }
    return state == "off" || state == "on"
  }

  private var reshadeStateNote: String? {
    if settings.reshade.working { return nil }
    switch settings.values["reshade_state"] {
    case "foreign":
      let dll = settings.values["reshade_dll"].flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
      return "Another ReShade is in the game folder\(dll). GW2 on Mac leaves it as it is."
    case "blocked":
      let blocker = names(settings.values["reshade_blocker"]) ?? "d3d11.dll"
      let files = blocker.contains(" and ") ? "those files" : "that file"
      return "The game folder has another \(blocker) (Nexus or another addon?). GW2 on Mac leaves it alone, so it can't add ReShade: remove \(files) first."
    case "nogame":
      return "The game is not installed yet: ReShade can go in once it is."
    default:
      return settings.running && settings.loaded ? "Quit the game and Steam to turn ReShade on or off." : nil
    }
  }

  // Add preset or shaders…: what a drop on the window takes (gw2om.sh refuses anything else, and
  // says why)
  private func chooseReshadeFiles() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.folder, .zip] + [UTType(filenameExtension: "ini")].compactMap { $0 }
    panel.message = "Choose ReShade presets (.ini), or zips or folders of presets and shaders"
    panel.prompt = "Add"
    if panel.runModal() == .OK { settings.importReshade(panel.urls) }
  }

  // The ReShade folder, once it exists (gw2om.sh prints it always): it stays when ReShade is off
  private var reshadeFolder: URL? {
    guard let path = settings.values["reshade_folder"], !path.isEmpty else { return nil }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private func interfaceStateNote(_ state: String) -> String {
    switch state {
    case "foreign": return "The game folder has another version.dll (another addon?). GW2 on Mac leaves it alone, so the larger interface is off."
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

// The warning before an addon is downloaded and goes in (as the larger interface's: off by
// default, a clear warning, installed only after the user confirms); its parts also ask whether
// a preset that came in should be ReShade's
struct AddonWarning: View {
  let title: String
  let bullets: [String]
  var icon = "triangle-alert"
  var confirmTitle = "Download and Turn On"
  @Binding var isPresented: Bool
  let confirm: () -> Void

  static func arcdps(isPresented: Binding<Bool>, confirm: @escaping () -> Void) -> AddonWarning {
    AddonWarning(title: "Turn on arcdps?", bullets: [
      "arcdps is a third-party addon by deltaconnected. It is not made or supported by ArenaNet, NCSOFT or GW2 on Mac.",
      "It reads the game's memory while it runs. Use it at your own risk: there is no help or warranty for it from GW2 on Mac.",
      "GW2 on Mac downloads it from deltaconnected.com and puts it into the game folder, next to Gw2-64.exe. From then on arcdps updates itself.",
      "Turning it off removes arcdps from the game folder and keeps its settings (addons/arcdps).",
    ], isPresented: isPresented, confirm: confirm)
  }

  // (version: gw2om.sh's reshade_version, the pinned one)
  static func reshade(isPresented: Binding<Bool>, version: String?, confirm: @escaping () -> Void) -> AddonWarning {
    let version = version.flatMap { $0.isEmpty ? nil : " " + $0 } ?? ""
    return AddonWarning(title: "Turn on ReShade?", bullets: [
      "ReShade is a third-party program by crosire. ArenaNet doesn't review, approve or endorse third-party programs, and neither ArenaNet nor I support it. You use it at your own risk.",
      "GW2 on Mac downloads ReShade\(version) from reshade.me and two effect packs from their authors on GitHub. ReShade goes into the game folder as d3d11.dll.",
      "Your presets and shaders live in a folder of their own, which stays when you turn ReShade off.",
      "Effects that read the depth buffer (ambient occlusion, depth of field) stay off in online games with this build of ReShade.",
    ], isPresented: isPresented, confirm: confirm)
  }

  // (name: as gw2om.sh's @preset line gives it)
  static func preset(isPresented: Binding<Bool>, name: String, confirm: @escaping () -> Void) -> AddonWarning {
    AddonWarning(title: "Use this preset now?", bullets: [
      "ReShade starts with \(name) the next time the game starts.",
      "Your other presets stay in the Presets folder. ReShade's menu (Home key) switches between them in the game.",
    ], icon: "sliders-horizontal", confirmTitle: "Use This Preset", isPresented: isPresented, confirm: confirm)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        LucideIcon(name: icon, size: 22).foregroundStyle(Brand.accent)
        Text(title).font(.head(19)).foregroundStyle(Brand.fg)
      }
      VStack(alignment: .leading, spacing: 8) {
        ForEach(bullets, id: \.self) { bullet($0) }
      }
      HStack {
        Spacer()
        Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
        Button(confirmTitle) { isPresented = false; confirm() }.keyboardShortcut(.defaultAction).tint(Brand.accent)
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

// One setting: its title and description on the left, the control on the right, and under the
// description, for a few rows, a line of SmallButtons
struct SettingRow<Control: View, Buttons: View>: View {
  let title: String
  let detail: String
  // a bar under the detail while something runs (0 to 1), as the install's steps draw theirs
  var progress: Double?
  @ViewBuilder var control: Control
  // (outside the control's VoiceOver label: each button reads its own title)
  @ViewBuilder var buttons: Buttons

  init(_ title: String, _ detail: String, progress: Double? = nil, @ViewBuilder control: () -> Control,
       @ViewBuilder buttons: () -> Buttons) {
    self.title = title
    self.detail = detail
    self.progress = progress
    self.control = control()
    self.buttons = buttons()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body(14, .bold)).bodyBox(14).foregroundStyle(Brand.fg)
        Text(detail).font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg2)
          .fixedSize(horizontal: false, vertical: true)
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
        // (no buttons, no line: the other rows stay as they were; one under the other when the
        // line doesn't fit)
        Group(subviews: buttons) { list in
          if !list.isEmpty {
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 8) { buttons }
              VStack(alignment: .leading, spacing: 6) { buttons }
            }
            .padding(.top, 4)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      control.labelsHidden().accessibilityLabel(Text(title))
    }
    .padding(.vertical, 11)
    .padding(.horizontal, 14)
    .accessibilityElement(children: .contain)
  }
}

extension SettingRow where Buttons == EmptyView {
  init(_ title: String, _ detail: String, progress: Double? = nil, @ViewBuilder control: () -> Control) {
    self.init(title, detail, progress: progress, control: control) { EmptyView() }
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
    let parts = [version.isEmpty ? "" : "GW2 on Mac \(version)",
                 AppActions.componentVersions().components(separatedBy: " · ").first ?? ""].filter { !$0.isEmpty }
    Text(parts.joined(separator: " · "))
      .font(.body(11)).bodyBox(11)
      .foregroundStyle(Brand.fg3)
      .textSelection(.enabled)
      .lineLimit(1)
      .padding(.horizontal, 10)
  }
}
