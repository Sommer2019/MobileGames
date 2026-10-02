import SwiftUI
import WidgetKit

/// Home screen widgets of Mobile Games.
@main
struct GameWidgetsBundle: WidgetBundle {
  var body: some Widget {
    DiceWidget()
    GameNightWidget()
  }
}

/// Shared with the app (home_widget writes here).
let appGroup = "group.de.sommer2019.mobileGames"
let sharedDefaults = UserDefaults(suiteName: appGroup) ?? .standard
