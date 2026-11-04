// The Play button, the window's primary action once everything is set up: gw2om.sh play starts
// the game in the bottle, the way the route installed it (Steam: steam.exe -applaunch 1284210;
// ArenaNet: the game's own launcher, Gw2-64.exe), with the settings of the Settings window. If the
// game already runs, the button brings it to the front instead.
//
// The game runs from the Game Mode bundle (gw2om.sh: <app dir>/gamemode/GW2.app, bundle id
// cz.jandrly.gw2onmac.game), so NSWorkspace sees it as that app.

import AppKit

extension Installer {
  nonisolated static let gameBundleID = "cz.jandrly.gw2onmac.game"

  // Starts the game (or brings it to the front); then: an error to show, or nil
  func play(then: @escaping (String?) -> Void) {
    if let game = NSRunningApplication.runningApplications(withBundleIdentifier: Installer.gameBundleID).first {
      game.activate()
      then(nil)
      return
    }
    guard ready else { then("Install Guild Wars 2 first."); return }
    guard !launching else { return }
    launching = true
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["play"])
      launching = false
      let error = output.contains("@done ") ? nil
        : output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "The game could not be started. Details are in ~/Library/Logs/GW2 on Mac/wine.log."
      refresh()
      then(error)
      if error == nil, UserDefaults.standard.bool(forKey: Installer.quitAfterLaunchKey) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
      }
    }
  }

  // Settings › Game: "Quit GW2 on Mac after launching" (off by default)
  static let quitAfterLaunchKey = "quitAfterLaunch"
}
