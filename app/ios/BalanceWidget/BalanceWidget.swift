import WidgetKit
import SwiftUI

/// Виджет «Баланс Интерры» для домашнего экрана.
///
/// Данные пишет приложение через home_widget в общий UserDefaults
/// (app group), ключи: balance_text («1 846,03 ₽») и balance_updated («14:05»).
private let appGroup = "group.ru.interra.lkInterra"

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: String
    let updated: String
}

struct BalanceProvider: TimelineProvider {
    private func load() -> BalanceEntry {
        let d = UserDefaults(suiteName: appGroup)
        return BalanceEntry(
            date: Date(),
            balance: d?.string(forKey: "balance_text") ?? "—",
            updated: d?.string(forKey: "balance_updated") ?? ""
        )
    }

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), balance: "1 846 ₽", updated: "12:00")
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        // Данные обновляет само приложение при каждом открытии кабинета;
        // сами перечитываем раз в полчаса на случай, если проспали пуш.
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct BalanceWidgetView: View {
    var entry: BalanceEntry

    // Фирменные цвета Интерры (AppColors в приложении).
    private let brand = Color(red: 0x3C / 255, green: 0x98 / 255, blue: 0xD4 / 255)
    private let accent = Color(red: 0xF4 / 255, green: 0x75 / 255, blue: 0x2D / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Text("Интерра")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            Text(entry.balance)
                .font(.system(size: 26, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(.white)
            Text(entry.updated.isEmpty ? "Баланс" : "Баланс · \(entry.updated)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [brand, accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

@main
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BalanceWidget", provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Баланс")
        .description("Текущий баланс лицевого счёта Интерры")
        .supportedFamilies([.systemSmall])
    }
}
