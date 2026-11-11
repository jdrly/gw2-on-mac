// The game's session as the launch panel follows it: after Play the panel shows the start's
// stages (Starting), then Playing with Bring to Front, and Ready again once the game has quit
// (with "Steam is closing…" while the watcher closes Steam). The window polls gw2om.sh
// session-status every second while a session runs, the same way it follows an install's
// progress, and stops when the session ends.

import AppKit
import SwiftUI

extension Installer {
  // A stage of the start (gw2om.sh session-status: stage=…)
  enum Stage: String, CaseIterable {
    case startingSteam = "starting_steam"
    case updatingSteam = "updating_steam"
    case signingIn = "signing_in"
    case checkingFiles = "checking_files"
    case startingGame = "starting_game"
    case loading
    case playing

    var title: String {
      switch self {
      case .startingSteam: "Starting Steam"
      case .updatingSteam: "Updating Steam"
      case .signingIn: "Signing in"
      case .checkingFiles: "Checking game files"
      case .startingGame: "Starting Guild Wars 2"
      case .loading: "Loading"
      case .playing: "Playing"
      }
    }
    // shown only when they happen
    var optional: Bool { self == .updatingSteam || self == .checkingFiles }
  }

  struct LaunchSession: Equatable {
    // the last session-status
    var values: [String: String] = [:]
    // when Play was pressed (or the window found the session running)
    var started = Date()
    var fromPlay: Bool
    var stage: Stage?
    var stageSince = Date()
    var seen: Set<Stage> = []
    var gameSeen = false
    // Show Steam brought Steam's window up, or why it didn't
    var steamShown = false
    var showSteamProblem: String?

    var arenanet: Bool { values["route"] == "arenanet" }
    var steamRunning: Bool { (values["steam"] ?? "none") != "none" }
    var steamWindow: Bool { steamShown || values["steam"] == "window" }
    var closing: Bool { values["closing"] == "yes" }
    // the watcher still follows the session (a restart's grace included): keep polling
    var watching: Bool { values["watching"] == "yes" }
    var quitsSteam: Bool { values["quit_steam"] == "yes" }
    var limiterHint: Bool { values["limiter_hint"] == "yes" }

    // The stages the panel lists: Steam's (the optional ones once they happened) and the game's
    var stages: [Stage] {
      let all: [Stage] = arenanet ? [.startingGame, .loading] : Stage.allCases.filter { $0 != .playing }
      return all.filter { !$0.optional || seen.contains($0) || stage == $0 }
    }

    // seconds since the start, and since the game started (Playing)
    var elapsed: Int { Int(values["elapsed"] ?? "") ?? Int(Date().timeIntervalSince(started)) }
    var gameElapsed: Int { Int(values["game_elapsed"] ?? "") ?? 0 }
    var progress: Double? { Double(values["progress"] ?? "").map { min(1, max(0, $0 / 100)) } }
    var detail: String { values["detail"] ?? "" }
  }

  // "0:42", "1:12:05"
  nonisolated static func clock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
  }

  // A start under way, the game running, or Steam closing after it
  var sessionStage: Stage? { session?.stage }

  // Follows the session: session-status every second until it has ended. fromPlay: Play was just
  // pressed (Wine takes a few seconds before Steam or the game shows up)
  func followSession(fromPlay: Bool) {
    if fromPlay || session == nil {
      var s = LaunchSession(fromPlay: fromPlay)
      if fromPlay {
        s.values["route"] = installedRoute == .arenanet ? "arenanet" : "steam"
        s.stage = installedRoute == .arenanet ? .startingGame : .startingSteam
      }
      session = s
    }
    // (a new Play replaces a running poller: a result it still waits for belongs to the old launch)
    if fromPlay, sessionTask != nil { stopPolling() }
    guard sessionTask == nil, ProcessInfo.processInfo.environment["GW2OM_RENDER"] == nil else { return }
    sessionGeneration += 1
    let generation = sessionGeneration
    let script = script
    sessionTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let arguments = self?.sessionStatusArguments else { break }
        let values = Installer.parseStatus(await Installer.capture(script: script, arguments: arguments))
        // (a poller stopped meanwhile, e.g. by a failed Play, leaves the next one's session alone)
        guard let self, !Task.isCancelled, self.sessionGeneration == generation, self.applySession(values) else { break }
        try? await Task.sleep(for: .seconds(1))
      }
      if let self, self.sessionGeneration == generation { self.sessionTask = nil }
    }
  }

  // session-status for the current session: a Play's own time, so its stages count from it, also
  // when it joined a running session (its Steam log lines, DXMT's log, the elapsed time)
  var sessionStatusArguments: [String] {
    guard let s = session, s.fromPlay else { return ["session-status"] }
    return ["session-status", "--since", String(Int(s.started.timeIntervalSince1970))]
  }

  // Stops the poller; a result it still waits for is dropped (its generation is gone)
  func stopPolling() {
    sessionTask?.cancel()
    sessionTask = nil
    sessionGeneration += 1
  }

  // Stops following (a Play that failed)
  func stopSession() {
    stopPolling()
    session = nil
  }

  // The latest session-status; false once the session has ended (the panel is Ready again)
  @discardableResult
  func applySession(_ values: [String: String]) -> Bool {
    guard var s = session, !values.isEmpty else { return session != nil }
    s.values = values
    var stage = Stage(rawValue: values["stage"] ?? "")
    if values["game"] == "yes" { s.gameSeen = true }
    // (just after Play: Wine is still starting Steam or the game)
    if stage == nil, s.fromPlay, !s.gameSeen, Date().timeIntervalSince(s.started) < 20 {
      stage = s.arenanet ? .startingGame : .startingSteam
    }
    if stage != s.stage { s.stageSince = Date() }
    s.stage = stage
    if let stage { s.seen.insert(stage) }
    if !s.steamRunning { s.steamShown = false }
    if stage == nil && !s.closing && !s.watching {
      session = nil
      sessionEnded = Date()
      // (the headless renders run no gw2om.sh)
      if ProcessInfo.processInfo.environment["GW2OM_RENDER"] == nil { refresh() }
      return false
    }
    session = s
    return true
  }

  // Bring to Front: the game's app (the Game Mode bundle)
  func bringGameToFront() {
    NSRunningApplication.runningApplications(withBundleIdentifier: Installer.gameBundleID).first?.activate()
  }

  // Show Steam: its window comes up (gw2om.sh show-steam: steam://open/main through the engine)
  func showSteam() {
    session?.showSteamProblem = nil
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["show-steam"])
      if output.contains("@done ") {
        session?.steamShown = true
      } else {
        // (it waits for the watcher's answer: Steam stays shut while it may still quit Steam)
        session?.showSteamProblem = output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "Steam's window could not be brought up."
      }
    }
  }

  // The frame-limiter hint's "Don't show again"
  static let limiterHintDismissedKey = "limiterHintDismissed"
}

// MARK: - Panels

// "● Steam in the background", "● Guild Wars 2 · 1:12", "● Installed · 0.1.1"
struct PanelChip: View {
  let pip: Color
  let text: String
  var body: some View {
    HStack(spacing: 6) {
      Pip(color: pip)
      Text(text).font(.body(12, .bold)).bodyBox(12).foregroundStyle(Brand.fg2).monospacedDigit()
    }
    .padding(.vertical, 3).padding(.horizontal, 8)
    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.borderStrong, lineWidth: 1))
  }
}

// A tip under the panel's actions (an icon in gold, or a spinner)
struct PanelTip: View {
  let icon: String
  let text: String
  var spinning = false
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if spinning {
        Spinner(size: 14).foregroundStyle(Brand.gold)
      } else {
        LucideIcon(name: icon, size: 14).foregroundStyle(Brand.gold)
      }
      Text(text).font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

// Lucide's loader-circle, turning
struct Spinner: View {
  var size: CGFloat = 13
  @State private var turning = false
  var body: some View {
    LucideIcon(name: "loader-circle", size: size)
      .rotationEffect(.degrees(turning ? 360 : 0))
      .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turning)
      .onAppear { turning = ProcessInfo.processInfo.environment["GW2OM_RENDER"] == nil }
  }
}

// Starting: the stages of the start (done, current, waiting), Show Steam, the time so far, a tip
struct StartingPanel: View {
  let installer: Installer
  let session: Installer.LaunchSession

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InkHeading(title: "Starting", size: 17, alignment: .center) {
        if !session.arenanet {
          PanelChip(pip: Brand.gold, text: session.steamWindow ? "Steam window" : "Steam in the background")
        }
      }
      let stages = session.stages
      VStack(spacing: 0) {
        ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
          StageRow(title: stage.title, state: state(stage, in: stages), last: index == stages.count - 1,
                   detail: stage == session.stage ? session.detail : "",
                   progress: stage == session.stage ? session.progress : nil)
        }
      }
      Rectangle().fill(Brand.border).frame(height: 1)
      HStack {
        if !session.arenanet {
          Button(action: installer.showSteam) {
            HStack(spacing: 7) {
              LucideIcon(name: "app-window", size: 14)
              Text("Show Steam").font(.body(13.5, .semibold)).bodyBox(13.5)
            }
            .foregroundStyle(Brand.fg)
            .padding(.vertical, 6).padding(.horizontal, 12)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.borderStrong, lineWidth: 1))
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .disabled(!session.steamRunning)
          .help("Brings Steam's window to the front, to sign in or see what it does")
        }
        Spacer()
        Text(Installer.clock(session.elapsed))
          .font(.body(13)).bodyBox(13).foregroundStyle(Brand.fg3).monospacedDigit()
          .accessibilityLabel("Time so far")
          .accessibilityValue(Installer.clock(session.elapsed))
      }
      PanelTip(icon: tipIcon, text: tip)
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .brandPanel()
  }

  private func state(_ stage: Installer.Stage, in stages: [Installer.Stage]) -> InstallingPanel.StepState {
    guard let current = session.stage, let i = stages.firstIndex(of: current), let j = stages.firstIndex(of: stage) else {
      return .todo
    }
    return j < i ? .done : j == i ? .current : .todo
  }

  // No sign-in after 2 minutes with Steam in the background: it may be asking in its window
  private var signInSlow: Bool {
    session.stage == .signingIn && !session.steamWindow && Date().timeIntervalSince(session.stageSince) > 120
  }

  private var tipIcon: String { signInSlow || session.showSteamProblem != nil ? "triangle-alert" : "info" }

  private var tip: String {
    if let problem = session.showSteamProblem { return problem }
    if session.arenanet { return "ArenaNet's launcher opens: log in there and press Play. Your login stays in it." }
    if signInSlow { return "Steam hasn't signed in yet. Show Steam: it may be asking you to sign in again." }
    if session.steamWindow { return "Sign in to Steam in its window if it asks. This window follows the start." }
    return session.quitsSteam
      ? "Steam runs in the background and closes again when you quit the game."
      : "Steam runs in the background while you play."
  }
}

// A stage in the Starting list: the install steps' markers at the design's 22 pt
struct StageRow: View {
  let title: String
  let state: InstallingPanel.StepState
  let last: Bool
  let detail: String
  let progress: Double?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        marker
        if !last {
          // (the design's rows: 30 pt, 56 with a progress bar; longer text stretches the line)
          Rectangle().fill(state == .done ? Brand.accent : Brand.border).frame(width: 2)
            .frame(idealHeight: progress == nil ? 8 : 34, maxHeight: .infinity)
        }
      }
      .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body(14, state == .todo ? .medium : .bold)).bodyBox(14)
          .foregroundStyle(state == .todo ? Brand.fg3 : Brand.fg)
        if !detail.isEmpty {
          Text(detail).font(.body(12.5)).bodyBox(12.5).foregroundStyle(Brand.fg3).lineLimit(1).monospacedDigit()
        }
        if let progress {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 3).fill(Brand.surface)
              RoundedRectangle(cornerRadius: 3).fill(Brand.accent).frame(width: geo.size.width * progress)
            }
          }
          .frame(height: 5)
          .padding(.top, 2)
        }
      }
      .padding(.top, 1)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityValue(state == .done ? "Done" : state == .current ? "In progress" : "Waiting")
  }

  @ViewBuilder private var marker: some View {
    ZStack {
      switch state {
      case .done:
        Circle().fill(Brand.accent)
        LucideIcon(name: "check", size: 12).foregroundStyle(Brand.onAccent)
      case .current:
        Circle().fill(Brand.accentSoft)
        Circle().strokeBorder(Brand.accent, lineWidth: 1.5)
        Spinner(size: 13).foregroundStyle(Brand.accent)
      case .todo:
        Circle().strokeBorder(Brand.borderStrong, lineWidth: 1.5)
        Circle().fill(Brand.borderStrong).frame(width: 6, height: 6)
      }
    }
    .frame(width: 22, height: 22)
  }
}

// Playing: Bring to Front, the secondary actions, a tip, and the frame-limiter hint
struct PlayingPanel: View {
  let installer: Installer
  let session: Installer.LaunchSession
  let actions: PanelActions
  @AppStorage(Installer.limiterHintDismissedKey) private var hintDismissed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InkHeading(title: "Playing", size: 17, alignment: .center) {
        PanelChip(pip: Brand.good, text: "Guild Wars 2 · \(Installer.clock(session.gameElapsed))")
      }
      Button(action: installer.bringGameToFront) {
        HStack(spacing: 10) {
          LucideIcon(name: "app-window", size: 18)
          Text("Bring to Front").font(.display(16)).tracking(1.6).textCase(.uppercase)
        }
        .foregroundStyle(Brand.accent)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        .background(Brand.accentSoft, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.accent, lineWidth: 1.5))
        .contentShape(.rect(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .help("Switches to the game")
      SecondaryActions(installer: installer, actions: actions)
      Rectangle().fill(Brand.border).frame(height: 1)
      if session.quitsSteam {
        PanelTip(icon: "store", text: "Steam closes by itself when you quit the game.")
      }
      if session.limiterHint && !hintDismissed {
        LimiterHint(value: session.values["limiter_value"] ?? "") { hintDismissed = true }
      }
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .brandPanel()
  }
}

// The game's own Frame Limiter with vsync lands just under the display's rate under Wine
struct LimiterHint: View {
  let value: String
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        LucideIcon(name: "gauge", size: 15).foregroundStyle(Brand.gold)
        Text("A steadier 60").font(.body(13.5, .bold)).bodyBox(13.5).foregroundStyle(Brand.fg)
      }
      Text(text).font(.body(12.5)).bodyBox(12.5, 1.3).foregroundStyle(Brand.fg2)
        .fixedSize(horizontal: false, vertical: true)
      Button("Don't show again", action: dismiss)
        .buttonStyle(QuietButtonStyle(color: Brand.accent))
        .font(.body(12.5, .bold)).bodyBox(12.5)
    }
    .padding(.vertical, 10).padding(.horizontal, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.goldSoft, in: .rect(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.gold, lineWidth: 1))
  }

  private var text: String {
    value == "60"
      ? "The game's own Frame Limiter is set to 60 with vsync on. Under Wine it lands at about 58 FPS; set "
        + "Options › Graphics › Frame Limiter to Unlimited and vsync keeps a steady 60."
      : "The game's own Frame Limiter is set to \(value) with vsync on. Under Wine the two together land just "
        + "under the display's rate; set Options › Graphics › Frame Limiter to Unlimited and vsync keeps it steady."
  }
}

// Repair, Settings, Uninstall… (Ready and Playing)
struct SecondaryActions: View {
  let installer: Installer
  let actions: PanelActions

  var body: some View {
    HStack {
      secondary("wrench", "Repair", Brand.fg, actions.repair)
        .help("Sets up the engine and the bottle's settings again; keeps the game and your settings")
      Spacer()
      secondary("sliders-horizontal", "Settings", Brand.fg, actions.settings)
      Spacer()
      secondary("trash-2", "Uninstall…", Brand.fg3, actions.uninstall)
    }
    .padding(.horizontal, 4)
  }

  private func secondary(_ icon: String, _ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        LucideIcon(name: icon, size: 14)
        Text(title).font(.body(13.5, .semibold)).bodyBox(13.5)
      }
    }
    .buttonStyle(QuietButtonStyle(color: color))
    .disabled(installer.isBusy)
  }
}
