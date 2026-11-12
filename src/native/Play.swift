// The Play button, the window's primary action once everything is set up: gw2om.sh play starts
// the game in the bottle, the way the route installed it (Steam: steam.exe -applaunch 1284210;
// ArenaNet: the game's own launcher, Gw2-64.exe), with the settings of the Settings window. If the
// game already runs, the button brings it to the front instead. While the game starts and runs,
// the panel follows its session (Session.swift).
//
// Every Wine process of this engine runs as its loader (bundle id app.mach9.loader), Steam's too,
// and so does a player's own Mach9.app: the game is found by its pid, which gw2om.sh status and
// session-status print (game_pid).

import AppKit

extension Installer {
  nonisolated static let loaderBundleID = "app.mach9.loader"

  // The game's process, if it runs: the pid of the last session-status, else of the last status,
  // still the engine's loader (a pid the game no longer has is no app or another app)
  var gameApp: NSRunningApplication? {
    for value in [session?.values["game_pid"], status["game_pid"]] {
      guard let pid = value.flatMap({ pid_t($0) }), let app = NSRunningApplication(processIdentifier: pid),
            !app.isTerminated, app.bundleIdentifier == Installer.loaderBundleID else { continue }
      return app
    }
    return nil
  }

  // Starts the game (or brings it to the front); then: a message to show (an error, or a notice
  // when it started), or nil
  func play(then: @escaping (_ message: String?, _ started: Bool) -> Void) {
    if let game = gameApp {
      game.activate()
      then(nil, true)
      return
    }
    guard ready else { then("Install Guild Wars 2 first.", false); return }
    guard !launching else { return }
    launching = true
    // the panel shows the start's stages right away (Session.swift)
    followSession(fromPlay: true)
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["play"])
      launching = false
      if !output.contains("@done ") { stopSession() }
      // an error, or a notice worth showing (Steam still runs with the settings it started with)
      let notice = output.split(separator: "\n").first { $0.hasPrefix("@notice ") }.map { String($0.dropFirst(8)) }
      let error = output.contains("@done ") ? notice
        : output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "The game could not be started. Details are in ~/Library/Logs/\(appFolder)/wine.log."
      // (a game the last status didn't know yet: up once status has its pid)
      refresh { if output.contains("already running") { self.gameApp?.activate() } }
      then(error, output.contains("@done "))
      if output.contains("@done "), UserDefaults.standard.bool(forKey: Installer.quitAfterLaunchKey) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
      }
    }
  }

  // Settings › Game: "Quit the app after launching" (off by default)
  static let quitAfterLaunchKey = "quitAfterLaunch"
}
