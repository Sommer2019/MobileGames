import AppIntents
import SwiftUI
import WidgetKit

/// 1–6 dice as a fixed choice: a picker instead of a number field, so no
/// invalid count can be entered.
enum DiceCount: Int, AppEnum {
  case one = 1, two, three, four, five, six

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Anzahl Würfel"
  static var caseDisplayRepresentations: [DiceCount: DisplayRepresentation] = [
    .one: "1 Würfel", .two: "2 Würfel", .three: "3 Würfel",
    .four: "4 Würfel", .five: "5 Würfel", .six: "6 Würfel",
  ]
}

/// Number of dice, set via "Edit widget".
struct DiceConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Würfel"
  static var description = IntentDescription("Wie viele Würfel sollen es sein?")

  @Parameter(title: "Anzahl Würfel", default: .two)
  var count: DiceCount
}

/// Last roll, kept between taps.
enum DiceStore {
  static var values: [Int] {
    get { (sharedDefaults.array(forKey: "dice.values") as? [Int]) ?? [1, 2, 3, 4, 5, 6] }
    set { sharedDefaults.set(newValue, forKey: "dice.values") }
  }

  static var rolled: Bool {
    get { sharedDefaults.bool(forKey: "dice.rolled") }
    set { sharedDefaults.set(newValue, forKey: "dice.rolled") }
  }

  static var rollId: Int {
    get { sharedDefaults.integer(forKey: "dice.rollId") }
    set { sharedDefaults.set(newValue, forKey: "dice.rollId") }
  }

  static func roll() {
    values = (0..<6).map { _ in Int.random(in: 1...6) }
    rolled = true
    rollId += 1
  }
}

/// Tapping the dice rolls them, right on the home screen.
struct RollDiceIntent: AppIntent {
  static var title: LocalizedStringResource = "Würfeln"

  func perform() async throws -> some IntentResult {
    DiceStore.roll()
    return .result()
  }
}

struct DiceEntry: TimelineEntry {
  let date: Date
  let count: Int
  let values: [Int]
  let rolled: Bool
  let rollId: Int

  var sum: Int { values.prefix(count).reduce(0, +) }
}

struct DiceProvider: AppIntentTimelineProvider {
  func entry(_ config: DiceConfig) -> DiceEntry {
    DiceEntry(
      date: Date(), count: config.count.rawValue, values: DiceStore.values,
      rolled: DiceStore.rolled, rollId: DiceStore.rollId)
  }

  func placeholder(in context: Context) -> DiceEntry {
    DiceEntry(date: Date(), count: 2, values: [3, 5, 1, 1, 1, 1], rolled: true, rollId: 0)
  }

  func snapshot(for configuration: DiceConfig, in context: Context) async -> DiceEntry {
    entry(configuration)
  }

  func timeline(for configuration: DiceConfig, in context: Context) async -> Timeline<DiceEntry> {
    Timeline(entries: [entry(configuration)], policy: .never)
  }
}

/// A white die with pips.
struct DieFace: View {
  let value: Int

  private static let pips: [Int: [CGPoint]] = [
    1: [CGPoint(x: 0.5, y: 0.5)],
    2: [CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.73, y: 0.73)],
    3: [CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.73, y: 0.73)],
    4: [
      CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.73, y: 0.27), CGPoint(x: 0.27, y: 0.73),
      CGPoint(x: 0.73, y: 0.73),
    ],
    5: [
      CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.73, y: 0.27), CGPoint(x: 0.5, y: 0.5),
      CGPoint(x: 0.27, y: 0.73), CGPoint(x: 0.73, y: 0.73),
    ],
    6: [
      CGPoint(x: 0.27, y: 0.24), CGPoint(x: 0.73, y: 0.24), CGPoint(x: 0.27, y: 0.5),
      CGPoint(x: 0.73, y: 0.5), CGPoint(x: 0.27, y: 0.76), CGPoint(x: 0.73, y: 0.76),
    ],
  ]

  var body: some View {
    GeometryReader { g in
      let s = min(g.size.width, g.size.height)
      ZStack {
        RoundedRectangle(cornerRadius: s * 0.18).fill(Color.white)
          .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        ForEach(Array((DieFace.pips[value] ?? []).enumerated()), id: \.offset) { _, p in
          Circle().fill(Color.black.opacity(0.85))
            .frame(width: s * 0.18, height: s * 0.18)
            .position(x: p.x * s, y: p.y * s)
        }
      }
      .frame(width: s, height: s)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

struct DiceWidgetView: View {
  let entry: DiceEntry

  private var rows: [[Int]] {
    let perRow = entry.count <= 3 ? entry.count : 3
    return stride(from: 0, to: entry.count, by: perRow).map {
      Array($0..<min($0 + perRow, entry.count))
    }
  }

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text(entry.count == 1 ? "1 Würfel" : "\(entry.count) Würfel")
          .font(.caption).foregroundStyle(.white.opacity(0.85))
        Spacer()
        Link(destination: URL(string: "mobilegames://dice?homeWidget")!) {
          Text("📳").font(.caption)
        }
      }
      Button(intent: RollDiceIntent()) {
        VStack(spacing: 6) {
          ForEach(rows, id: \.self) { row in
            HStack(spacing: 6) {
              ForEach(row, id: \.self) { i in
                DieFace(value: entry.values[i])
                  .id("\(entry.rollId)-\(i)")
                  .transition(.scale(scale: 0.2).combined(with: .opacity))
              }
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .buttonStyle(.plain)
      Text(
        entry.rolled
          ? (entry.count == 1 ? "Gewürfelt: \(entry.sum)" : "Summe: \(entry.sum)")
          : "Tippen zum Würfeln"
      )
      .font(.caption).foregroundStyle(.white)
      .contentTransition(.numericText())
    }
    .containerBackground(for: .widget) {
      Color(red: 0.11, green: 0.37, blue: 0.13)
    }
  }
}

struct DiceWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "DiceWidget", intent: DiceConfig.self, provider: DiceProvider()) {
      entry in
      DiceWidgetView(entry: entry)
    }
    .configurationDisplayName("Würfel")
    .description("1–6 Würfel, antippen zum Würfeln. Anzahl über „Widget bearbeiten“.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
