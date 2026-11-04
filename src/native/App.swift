// GW2 on Mac: the app (SwiftUI). The main window (MainWindow.swift) shows this Mac's state and
// the launch panel, and runs Resources/gw2om.sh (status, install, finish, repair, uninstall,
// play), which does the actual work and streams its progress back as "@" lines (see the header
// of app/src/gw2om.sh). Also here: the app menu (About, Check for Updates…, Settings…, Collect
// Logs…, Quit), with Settings.swift (the Settings window) and Updates.swift (Sparkle, off until
// there is a feed).
//
// Unlike SWTOR on Mac, GW2 on Mac changes no existing install: it creates its own engine, bottle
// and graphics, and installs the game into them through Steam or ArenaNet's own installer.
//
// GW2_ON_MAC_ROOT and GW2_ON_MAC_DRY_RUN in the app's environment are passed on to gw2om.sh (and
// collect-logs.sh), so the window can be tried against a sandbox:
//   GW2_ON_MAC_ROOT=/tmp/gw2om-sandbox "GW2 on Mac.app/Contents/MacOS/GW2onMac"

import AppKit
import SwiftUI

// MARK: - Model

@MainActor @Observable
final class Installer {
  enum Route: String, CaseIterable { case steam, arenanet }
  enum Operation: String { case install, finish, repair, uninstall }
  enum Phase: Equatable {
    case idle
    case working(Operation)
    // Steam or ArenaNet's installer is downloading the game; the window follows it (status)
    case waitingForGame
    case succeeded(Operation, String)
    case failed(Operation, String)
  }
  // A step of the timeline: gw2om.sh announces each with "@phase <n>"
  struct Step: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
  }
  struct Progress: Equatable { var label: String; var done: Int64; var total: Int64 }

  static func installSteps(_ route: Route, interface: Bool) -> [Step] {
    let finishing = Step(id: 5, title: "Finishing touches",
                         detail: interface ? "The sharper interface and the shader cache" : "Game Mode and the shader cache")
    let common = [
      Step(id: 1, title: "The Wine engine", detail: "CrossOver 26.3 · from athei/wine-build"),
      Step(id: 2, title: "The game's own bottle", detail: "Retina, Game Mode and our graphics"),
    ]
    switch route {
    case .steam:
      return common + [
        Step(id: 3, title: "Steam, from Valve", detail: "SteamSetup.exe, Valve's installer"),
        Step(id: 4, title: "Sign in, then install Guild Wars 2", detail: "Steam opens. Your login stays in Steam."),
        finishing,
      ]
    case .arenanet:
      return common + [
        Step(id: 3, title: "ArenaNet's installer", detail: "Gw2Setup-64.exe, the file you chose"),
        Step(id: 4, title: "Install Guild Wars 2", detail: "ArenaNet's installer opens and downloads the game."),
        finishing,
      ]
    }
  }
  static let uninstallSteps = [
    Step(id: 1, title: "Stop the game's Wine", detail: "Steam, the game and their Wine session"),
    Step(id: 2, title: "Remove the bottle", detail: "With the game's files in it"),
    Step(id: 3, title: "Remove the engine and caches", detail: "And GW2 on Mac's settings; the logs stay"),
  ]

  var status: [String: String] = [:]
  var phase: Phase = .idle
  var step = ""
  var progress: Progress?
  var log: [String] = []
  var warnings: [String] = []
  // the operation shown in the step list, and how far it got
  var operation: Operation = .install
  var stepIndex: Int?
  // The route chosen in the window (kept across launches), and the ArenaNet installer the user
  // dropped (checked by gw2om.sh check-setup)
  var route: Route = Route(rawValue: UserDefaults.standard.string(forKey: "route") ?? "") ?? .steam {
    didSet { UserDefaults.standard.set(route.rawValue, forKey: "route") }
  }
  var setupFile: URL?
  var setupCheck: SetupCheck?
  enum SetupCheck: Equatable { case checking, ok(String), bad(String) }
  // a sheet or alert is open on the main window (it keeps the app from quitting), and a request
  // to close them
  var sheetOpen = false
  var closeSheets = 0
  let credits: [String: String]
  // the Play button is starting the game (Play.swift)
  var launching = false
  // an operation has ended (a held app update may go ahead)
  var onIdle: (() -> Void)?

  private var process: Process?
  let script = Brand.resources.appendingPathComponent("gw2om.sh")

  init() {
    credits = Installer.readProperties(Brand.resources.appendingPathComponent("app.properties"))
  }

  // MARK: Derived state

  var isOperating: Bool { if case .working = phase { true } else { false } }
  var isBusy: Bool { isOperating }
  var loaded: Bool { !status.isEmpty }
  var rosetta: Bool { status["rosetta"] == "yes" }
  var appleSilicon: Bool { status["arch"].map { $0 == "arm64" } ?? true }
  // the setup (engine, bottle and graphics) is in place
  var installed: Bool { status["installed"] == "yes" }
  var gameInstalled: Bool { status["game"] == "yes" }
  // everything is done: Play
  var ready: Bool { installed && gameInstalled && status["stage"] == "finished" }
  var installedRoute: Route? { Route(rawValue: status["route"] ?? "") }
  var appVersion: String { credits["version"] ?? "?" }
  var installedVersion: String { status["installed_version"] ?? appVersion }
  var installedOtherVersion: Bool { installed && installedVersion != appVersion }
  var diskFree: Int64 { Int64(status["disk_free"] ?? "") ?? 0 }
  var diskNeeded: Int64 { Int64(status["disk_needed"] ?? "") ?? 75_000_000_000 }
  var diskLow: Bool { loaded && !gameInstalled && diskFree > 0 && diskFree < diskNeeded }
  // What runs (gw2om.sh status "busy"): game, steam, installer (ArenaNet's), session (the
  // bottle's Wine), leftovers, none
  var busy: String { status["busy"] ?? "none" }
  var gameRunning: Bool { busy == "game" }

  // The steps shown: the install's (of the route being installed), or the uninstall's
  var steps: [Step] {
    operation == .uninstall ? Installer.uninstallSteps
      : Installer.installSteps(installedRoute ?? route, interface: status["uiscale"] == "on")
  }

  // The panel the right column shows
  enum Panel { case choose, installing, ready }
  var panel: Panel {
    switch phase {
    case .working(.uninstall): return .installing
    case .working, .waitingForGame: return .installing
    default: return ready ? .ready : .choose
    }
  }

  // Why Install can't go ahead, or nil
  var installBlocker: String? {
    if !loaded { return "Checking this Mac…" }
    if !appleSilicon { return "GW2 on Mac needs a Mac with Apple silicon." }
    if !rosetta { return "Install Rosetta first: softwareupdate --install-rosetta in Terminal." }
    if route == .arenanet {
      switch setupCheck {
      case .ok: break
      case .checking: return "Checking Gw2Setup-64.exe…"
      case .bad(let why): return why
      case nil: return "Drop Gw2Setup-64.exe from ArenaNet's site first."
      }
    }
    return nil
  }

  // MARK: Actions

  func refresh(then: (() -> Void)? = nil) {
    guard !isOperating else { then?(); return }
    Task {
      let values = Installer.parseStatus(await Installer.capture(script: script, arguments: ["status"]))
      applyStatus(values)
      then?()
    }
  }

  private func applyStatus(_ values: [String: String]) {
    status = values
    // A game install that waits for Steam or ArenaNet's installer picks up where it was after
    // the app restarts; once the game is there, the finishing touches run (once: a failed finish
    // waits for Install or Repair)
    guard !isOperating else { return }
    if values["stage"] == "waiting_game" {
      if values["game"] == "yes" {
        if phase != .failed(.finish, lastFinishError) { start(.finish) }
      } else {
        operation = .install
        phase = .waitingForGame
        stepIndex = 3
        let done = Int64(values["game_bytes"] ?? "") ?? 0, total = Int64(values["game_total"] ?? "") ?? 0
        // (ArenaNet's installer: how much is there, no total)
        progress = done > 0 || total > 0 ? Progress(label: "Guild Wars 2", done: done, total: total) : nil
        scheduleGameWatch()
      }
    } else if phase == .waitingForGame {
      phase = .idle
    }
  }
  private var lastFinishError: String {
    if case .failed(.finish, let m) = phase { return m }
    return ""
  }

  // While Steam or ArenaNet's installer downloads the game: a look every few seconds (status
  // reads Steam's appmanifest or the game folder; nothing else runs)
  private var watch: DispatchWorkItem?
  private func scheduleGameWatch() {
    watch?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { if self?.phase == .waitingForGame { self?.refresh() } }
    }
    watch = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
  }

  // Stop waiting for the game: the engine and the bottle stay (Install picks up from there)
  func stopWaiting() {
    guard phase == .waitingForGame else { return }
    Task {
      _ = await Installer.capture(script: script, arguments: ["stop-waiting"])
      phase = .idle
      refresh()
    }
  }

  // Checks a dropped installer (PE x86_64, signed by ArenaNet) with gw2om.sh check-setup
  func choose(setup url: URL) {
    route = .arenanet
    setupFile = url
    setupCheck = .checking
    Task {
      let output = await Installer.capture(script: script, arguments: ["check-setup", url.path])
      guard setupFile == url else { return }
      if let ok = output.split(separator: "\n").first(where: { $0.hasPrefix("@done ") }) {
        setupCheck = .ok(String(ok.dropFirst(6)))
      } else {
        setupCheck = .bad(output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
                          ?? "This is not ArenaNet's Gw2Setup-64.exe.")
      }
    }
  }

  func start(_ operation: Operation) {
    guard !isOperating else { return }
    phase = .working(operation)
    self.operation = operation
    stepIndex = operation == .finish ? 4 : nil
    step = operation == .uninstall ? "Removing…" : "Starting…"
    progress = nil
    log = []
    warnings = []
    watch?.cancel()

    var arguments = [script.path, operation.rawValue]
    if operation == .install {
      arguments.append(route.rawValue)
      if route == .arenanet, let setupFile { arguments.append(setupFile.path) }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let reader = LineReader { [weak self] line in
      Task { @MainActor in self?.handle(line) }
    }
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        reader.finish()
      } else {
        reader.feed(data)
      }
    }
    process.terminationHandler = { [weak self] p in
      let status = p.terminationStatus
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        MainActor.assumeIsolated { self?.finished(operation, status) }
      }
    }
    do {
      try process.run()
      self.process = process
    } catch {
      phase = .failed(operation, "Could not start the installer: \(error.localizedDescription)")
    }
  }

  // Cancel: the script stops and rolls back what this run created (SIGTERM, its trap)
  func cancel() {
    if phase == .waitingForGame { stopWaiting() } else { process?.terminate() }
  }

  private var lastError: String?
  private var doneMessage: String?

  private func handle(_ line: String) {
    if line.hasPrefix("@step ") {
      step = String(line.dropFirst(6))
      progress = nil
      log.append("▸ " + step)
    } else if line.hasPrefix("@phase ") {
      if let n = Int(line.dropFirst(7)), n >= 1, n <= steps.count { stepIndex = n - 1; progress = nil }
    } else if line.hasPrefix("@progress ") {
      let parts = line.split(separator: " ")
      if parts.count >= 4, let done = Int64(parts[parts.count - 2]), let total = Int64(parts[parts.count - 1]) {
        progress = Progress(label: parts[1..<(parts.count - 2)].joined(separator: " "), done: done, total: total)
      }
    } else if line.hasPrefix("@warn ") {
      let text = String(line.dropFirst(6))
      warnings.append(text)
      log.append("⚠︎ " + text)
    } else if line.hasPrefix("@error ") {
      lastError = String(line.dropFirst(7))
      log.append("✕ " + lastError!)
    } else if line.hasPrefix("@done ") {
      doneMessage = String(line.dropFirst(6))
    } else {
      log.append(line)
    }
  }

  private func finished(_ operation: Operation, _ status: Int32) {
    process = nil
    progress = nil
    if status == 0 {
      phase = .succeeded(operation, doneMessage ?? "Done.")
    } else if status == 143 || status == 15 {
      phase = .failed(operation, "Cancelled. Nothing of this run was kept.")
    } else {
      phase = .failed(operation, lastError ?? "Something went wrong (status \(status)). Details are in the log.")
    }
    lastError = nil
    doneMessage = nil
    refresh()
    onIdle?()
  }

  // MARK: Helpers

  static func capture(script: URL, arguments: [String]) async -> String {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path] + arguments
      process.standardInput = FileHandle.nullDevice
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        continuation.resume(returning: "")
        return
      }
      DispatchQueue.global().async {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        continuation.resume(returning: String(decoding: data, as: UTF8.self))
      }
    }
  }

  // KEY=VALUE lines
  nonisolated static func parseStatus(_ output: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in output.split(separator: "\n") {
      guard let eq = line.firstIndex(of: "="), !line.hasPrefix("@") else { continue }
      values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
  }

  // Resources/app.properties (written by build.sh): version, author, github, repo, feed
  static func readProperties(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    return parseStatus(text)
  }

  // "412 GB" (decimal, as Finder counts)
  nonisolated static func gigabytes(_ bytes: Int64) -> String {
    "\(Int((Double(bytes) / 1e9).rounded())) GB"
  }

  nonisolated static func megabytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1e6
    return mb < 10 ? String(format: "%.1f", mb) : String(Int(mb.rounded()))
  }
}

// Splits a byte stream into lines (the pipe hands over arbitrary chunks).
final class LineReader: @unchecked Sendable {
  private var buffer = Data()
  private let lock = NSLock()
  private let emit: (String) -> Void

  init(emit: @escaping (String) -> Void) { self.emit = emit }

  func feed(_ data: Data) {
    lock.lock()
    buffer.append(data)
    var lines: [String] = []
    while let nl = buffer.firstIndex(of: 0x0A) {
      lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
      buffer.removeSubrange(buffer.startIndex...nl)
    }
    lock.unlock()
    lines.forEach(emit)
  }

  func finish() {
    lock.lock()
    let rest = buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    buffer.removeAll()
    lock.unlock()
    if let rest { emit(rest) }
  }
}

// MARK: - App menu actions

// Where to get help: the Discord server SWTOR on Mac and gw2onmac.com use, and GitHub issues
enum Support {
  static let discord = URL(string: "https://discord.gg/AnV3fZWz2b")!
  static let issues = URL(string: "https://github.com/jdrly/gw2-on-mac/issues")!
}

// The design's disclaimer (the window's footer, the badge's popover, About)
let disclaimer = "Unofficial. Not made, endorsed or supported by ArenaNet or NCSOFT. Guild Wars 2 is a "
  + "trademark of NCSOFT Corporation."

@MainActor
enum AppActions {
  static func showAbout(credits: [String: String]) {
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    let body: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
      .foregroundColor: NSColor.labelColor, .paragraphStyle: centered]
    let text = NSMutableAttributedString(string:
      "Guild Wars 2 on its own Wine engine, with DXMT (Direct3D 11 on Metal)\n"
      + "Developed by \(credits["author"] ?? "Jan Drlý")\n\n"
      + "An unofficial fan project. " + disclaimer + "\n"
      + "For help: Pharaphobia on Discord or a GitHub issue, never ArenaNet's support.\n", attributes: body)
    for link in [Support.discord, Support.issues] {
      var attributes = body
      attributes[.link] = link
      text.append(NSAttributedString(string: "\n", attributes: body))
      text.append(NSAttributedString(string: link.absoluteString.replacingOccurrences(of: "https://", with: ""), attributes: attributes))
    }
    for key in ["repo", "github"] {
      guard let url = credits[key], !url.isEmpty, let link = URL(string: url) else { continue }
      var attributes = body
      attributes[.link] = link
      text.append(NSAttributedString(string: "\n", attributes: body))
      text.append(NSAttributedString(string: url.replacingOccurrences(of: "https://", with: ""), attributes: attributes))
    }
    #if GW2_DEV
    let devSuffix = " (development build)"
    #else
    let devSuffix = ""
    #endif
    var small = body
    small[.font] = NSFont.systemFont(ofSize: NSFont.labelFontSize - 1)
    small[.foregroundColor] = NSColor.secondaryLabelColor
    text.append(NSAttributedString(string: "\n\n" + componentVersions(), attributes: small))
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "GW2 on Mac",
      .applicationVersion: (credits["version"] ?? "?") + devSuffix,
      .version: "",
      .credits: text,
    ])
  }

  // "DXMT 684f428 · Wine cx-26.3.0-8 · Sparkle 2.10.0" from Resources/VERSIONS
  static func componentVersions() -> String {
    let url = Brand.resources.appendingPathComponent("VERSIONS")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    var parts: [String] = []
    for line in text.split(separator: "\n") {
      let f = line.split(separator: " ")
      guard f.count >= 2 else { continue }
      if f[0] == "dxmt" { parts.append("DXMT \(f[1])") }
      if f[0] == "engine" { parts.append("Wine \(f[1])") }
      if f[0] == "sparkle" { parts.append("Sparkle \(f[1])") }
    }
    return parts.joined(separator: " · ")
  }
}

// Collect Logs…: Resources/collect-logs.sh zips the logs for a bug report (off the main thread;
// the menu item says "Collecting Logs…" meanwhile) and prints the zip's path; then say where it
// is and show it in Finder.
@MainActor @Observable
final class LogCollector {
  var busy = false

  func collect() {
    guard !busy else { return }
    busy = true
    let script = Brand.resources.appendingPathComponent("collect-logs.sh")
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path]
      process.standardInput = FileHandle.nullDevice
      let output = Pipe(), errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      var zip: String?, problem: String?
      do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
          .components(separatedBy: "\n").last ?? ""
        if process.terminationStatus == 0, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
          zip = path
        } else {
          problem = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
      } catch {
        problem = error.localizedDescription
      }
      DispatchQueue.main.async { [zip, problem] in
        MainActor.assumeIsolated { self.finished(zip: zip, problem: problem) }
      }
    }
  }

  private func finished(zip: String?, problem: String?) {
    busy = false
    let alert = NSAlert()
    if let zip {
      let folder = FileManager.default.displayName(atPath: (zip as NSString).deletingLastPathComponent)
      alert.messageText = "Logs collected"
      alert.informativeText = "\((zip as NSString).lastPathComponent) is in your \(folder) folder. Send it with a "
        + "short description of the problem to Pharaphobia on Discord or attach it to a GitHub issue, "
        + "not to ArenaNet's support. It includes "
        + "the crash reports of the game, Wine and GW2 on Mac from the last 7 days, and contains no "
        + "account names or passwords."
      alert.addButton(withTitle: "Show in Finder")
    } else {
      alert.alertStyle = .warning
      alert.messageText = "Could not collect the logs"
      alert.informativeText = "\(problem?.isEmpty == false ? problem! : "collect-logs.sh failed.")\n\n"
        + "The logs are in ~/Library/Logs/GW2 on Mac."
    }
    NSApp.activate()
    alert.runModal()
    if let zip { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: zip)]) }
  }
}

struct AppCommands: Commands {
  let installer: Installer
  let updates: Updates
  let settings: GameSettings
  let logs: LogCollector
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About GW2 on Mac") { AppActions.showAbout(credits: installer.credits) }
      Button("Check for Updates…") { updates.checkForUpdates() }
        .disabled(!updates.available)
    }
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") {
        settings.reload()
        openWindow(id: "settings")
      }
      .keyboardShortcut(",")
      .disabled(!installer.installed)
      Button(logs.busy ? "Collecting Logs…" : "Collect Logs…") { logs.collect() }
        .disabled(logs.busy)
    }
    CommandGroup(replacing: .newItem) {}
    CommandGroup(replacing: .help) {
      Link("Get Help on Discord", destination: Support.discord)
      Link("Report a Problem on GitHub", destination: Support.issues)
    }
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
  var installer: Installer?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  // Not while installing or uninstalling: the script finishes or rolls back first. (Waiting for
  // Steam or ArenaNet's installer to download the game doesn't hold it: the next start picks up.)
  @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let installer, installer.isBusy else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "GW2 on Mac is still working"
    alert.informativeText = "Wait until it has finished, or press Cancel in the window first."
    alert.runModal()
    return .terminateCancel
  }
}

// (app/scripts/ui-render.swift brings its own entry point)
#if !GW2_RENDER
@main
#endif
struct GW2onMacApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  private let installer: Installer
  private let updates = Updates()
  private let settings = GameSettings()
  private let logs = LogCollector()

  init() {
    Brand.registerFonts()
    installer = Installer()
  }

  var body: some Scene {
    Window("GW2 on Mac", id: "main") {
      MainView(installer: installer, settings: settings)
        .onAppear {
          delegate.installer = installer
          settings.updates = updates
          updates.isBusy = { [installer] in installer.isBusy }
          updates.sheetOpen = { [installer] in installer.sheetOpen }
          updates.closeSheets = { [installer] in installer.closeSheets += 1 }
          installer.onIdle = { [updates] in updates.installerIdle() }
          updates.start()
          installer.refresh()
          settings.reload()
          NSApp.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          installer.refresh()
        }
        // Settings › Troubleshooting's Collect…
        .onReceive(NotificationCenter.default.publisher(for: .collectLogs)) { _ in logs.collect() }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    .defaultSize(width: MainView.designSize.width, height: MainView.designSize.height)
    .restorationBehavior(.disabled)
    .commands { AppCommands(installer: installer, updates: updates, settings: settings, logs: logs) }

    // A window, not a Settings scene: its menu item can then be disabled until GW2 on Mac is set up
    Window("GW2 on Mac Settings", id: "settings") {
      SettingsView(settings: settings)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    .defaultSize(width: SettingsView.designSize.width, height: SettingsView.designSize.height)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}
