import SwiftUI
import WidgetKit

struct RecentGame: Decodable, Hashable {
  let id: String
  let title: String
}

struct GameNightEntry: TimelineEntry {
  let date: Date
  let unread: Int
  let requests: Int
  let onlineCount: Int
  let online: String
  let recent: [RecentGame]

  /// When the app last pushed data; nil if it never arrived (e.g. the app
  /// group was lost when the app was signed).
  let updated: Date?

  /// What the app last pushed (lib/core/home_widgets.dart).
  static func load() -> GameNightEntry {
    let d = sharedDefaults
    let json = d.string(forKey: "recent") ?? "[]"
    let recent = (try? JSONDecoder().decode([RecentGame].self, from: Data(json.utf8))) ?? []
    return GameNightEntry(
      date: Date(), unread: d.integer(forKey: "unread"), requests: d.integer(forKey: "requests"),
      onlineCount: d.integer(forKey: "onlineCount"), online: d.string(forKey: "online") ?? "",
      recent: recent, updated: updatedDate(d))
  }
}

/// home_widget stores numbers as Int or Int64; 0 = never written.
func updatedDate(_ d: UserDefaults) -> Date? {
  let seconds = d.double(forKey: "updated")
  return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
}

struct GameNightProvider: TimelineProvider {
  func placeholder(in context: Context) -> GameNightEntry {
    GameNightEntry(
      date: Date(), unread: 2, requests: 1, onlineCount: 2, online: "Anna, Ben",
      recent: [RecentGame(id: "chess", title: "Schach"), RecentGame(id: "yahtzee", title: "Würfelkönig")],
      updated: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (GameNightEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : GameNightEntry.load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GameNightEntry>) -> Void) {
    // The app reloads the widget when something changes.
    let next = Date().addingTimeInterval(30 * 60)
    completion(Timeline(entries: [GameNightEntry.load()], policy: .after(next)))
  }
}

struct Badge: View {
  let text: String
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.white)
      .padding(.horizontal, 8).padding(.vertical, 2)
      .background(Color.white.opacity(0.2), in: Capsule())
  }
}

struct GameNightView: View {
  @Environment(\.widgetFamily) var family
  let entry: GameNightEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("🎮 Spieleabend").font(.subheadline.bold()).foregroundStyle(.white)
        Spacer()
        Badge(text: "💬 \(entry.unread)")
        if family != .systemSmall { Badge(text: "👋 \(entry.requests)") }
      }
      Text(
        entry.onlineCount == 0
          ? "Kein Freund online" : "🟢 \(entry.onlineCount) online: \(entry.online)"
      )
      .font(.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
      Group {
        if let updated = entry.updated {
          Text("Stand: \(updated, style: .time)")
        } else {
          Text("Noch keine Daten – öffne die App einmal")
        }
      }
      .font(.caption2).foregroundStyle(.white.opacity(0.6))
      Spacer(minLength: 0)
      if family != .systemSmall {
        HStack(spacing: 6) {
          ForEach(entry.recent.prefix(3), id: \.self) { g in
            Link(destination: URL(string: "mobilegames://game/\(g.id)?homeWidget")!) {
              Text("▶ \(g.title)").font(.caption).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
          }
        }
      }
    }
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color(red: 0.25, green: 0.32, blue: 0.71), Color(red: 0.1, green: 0.14, blue: 0.49)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .widgetURL(URL(string: "mobilegames://home?homeWidget"))
  }
}

struct GameNightWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "GameNightWidget", provider: GameNightProvider()) { entry in
      GameNightView(entry: entry)
    }
    .configurationDisplayName("Spieleabend")
    .description("Nachrichten, Freunde online und deine letzten Spiele.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
