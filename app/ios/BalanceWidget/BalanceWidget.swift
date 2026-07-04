import WidgetKit
import SwiftUI
import AppIntents

/// интент кнопки «Обновить» на виджете: тянет свежий баланс из биллинга
/// прямо из процесса виджета (токен зеркалирован в app group)
struct RefreshBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Обновить баланс"
    static let description = IntentDescription("Запрашивает актуальный баланс")

    func perform() async throws -> some IntentResult {
        await BalanceCore.refresh()
        return .result()
    }
}

// MARK: - Конфигурация виджета

/// Что показывать в виджете (выбирается долгим тапом → «Редактировать»)
enum BalanceMetric: String, AppEnum {
    case balance
    case account

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Показатель" }
    static var caseDisplayRepresentations: [BalanceMetric: DisplayRepresentation] {
        [.balance: "Баланс", .account: "Лицевой счёт"]
    }
}

struct BalanceWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Виджет Интерры" }
    static var description: IntentDescription { IntentDescription("Что показывать в виджете") }

    @Parameter(title: "Показатель", default: .balance)
    var metric: BalanceMetric
}

// MARK: - Данные

/// Данные пишет приложение через home_widget в общий UserDefaults (app group):
/// balance_text («1 846,03 ₽»), account_text («504600»), balance_updated («14:05»)
private let appGroup = "group.ru.interra.lkInterra"

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: String
    let account: String
    let updated: String
    let metric: BalanceMetric

    /// значение для выбранного показателя (или «нет данных»)
    var value: String {
        switch metric {
        case .balance: return (balance.isEmpty || balance == "—") ? "нет данных" : balance
        case .account: return account.isEmpty ? "нет данных" : account
        }
    }

    var label: String { metric == .balance ? "Баланс" : "Лицевой счёт" }

    var hasData: Bool {
        switch metric {
        case .balance: return balance != "—" && !balance.isEmpty
        case .account: return !account.isEmpty
        }
    }

    /// минус - только для баланса (для account неприменимо)
    var isNegative: Bool {
        metric == .balance && (balance.hasPrefix("\u{2212}") || balance.hasPrefix("-"))
    }
}

struct BalanceProvider: AppIntentTimelineProvider {
    typealias Entry = BalanceEntry
    typealias Intent = BalanceWidgetConfig

    private func load(_ metric: BalanceMetric) -> BalanceEntry {
        let d = UserDefaults(suiteName: appGroup)
        return BalanceEntry(
            date: Date(),
            balance: d?.string(forKey: "balance_text") ?? "—",
            account: d?.string(forKey: "account_text") ?? "",
            updated: d?.string(forKey: "balance_updated") ?? "",
            metric: metric)
    }

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), balance: "1 846,03 ₽", account: "504600",
                     updated: "12:00", metric: .balance)
    }

    func snapshot(for configuration: BalanceWidgetConfig, in context: Context) async -> BalanceEntry {
        load(configuration.metric)
    }

    func timeline(for configuration: BalanceWidgetConfig, in context: Context) async -> Timeline<BalanceEntry> {
        // данные обновляет приложение (при открытии) и фоновый рефреш; сами
        // перечитываем раз в полчаса на случай, если проспали обновление
        Timeline(entries: [load(configuration.metric)],
                 policy: .after(Date().addingTimeInterval(1800)))
    }
}

// MARK: - Палитра

private enum Palette {
    static let brand = Color(red: 0x3C / 255, green: 0x98 / 255, blue: 0xD4 / 255)
    static let brandDeep = Color(red: 0x2B / 255, green: 0x7A / 255, blue: 0xB4 / 255)
    static let accent = Color(red: 0xF4 / 255, green: 0x75 / 255, blue: 0x2D / 255)
    static let danger = Color(red: 0xE5 / 255, green: 0x3E / 255, blue: 0x3E / 255)
}

/// фон: диагональный фирменный градиент + мягкий световой блик для объёма.
/// При минусе баланса уводим в тёплый красновато-оранжевый
private struct WidgetBackground: View {
    let negative: Bool
    var body: some View {
        ZStack {
            LinearGradient(
                colors: negative
                    ? [Palette.accent, Palette.danger]
                    : [Palette.brand, Palette.brandDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color.white.opacity(0.28), Color.clear],
                center: .topLeading, startRadius: 0, endRadius: 180)
        }
    }
}

private struct BrandMark: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.20))
            Image(systemName: "wifi")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct RefreshButton: View {
    var size: CGFloat = 26
    var body: some View {
        Button(intent: RefreshBalanceIntent()) {
            ZStack {
                Circle().fill(Color.white.opacity(0.20))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small

private struct SmallBalanceView: View {
    let entry: BalanceEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandMark(size: 24)
                Spacer()
                RefreshButton(size: 24)
            }
            Spacer(minLength: 6)
            Text(entry.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.75))
            Text(entry.value)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            if !entry.updated.isEmpty {
                Text("обновлено \(entry.updated)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 2)
            } else if !entry.hasData {
                Text("откройте приложение")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

private struct MediumBalanceView: View {
    let entry: BalanceEntry
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    BrandMark(size: 28)
                    Text("Интерра")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 8)
                Text(entry.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.75))
                Text(entry.value)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(entry.updated.isEmpty
                        ? "откройте приложение"
                        : "обновлено в \(entry.updated)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                if entry.metric == .balance {
                    HStack(spacing: 5) {
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                        Text(entry.isNegative ? "Пополните" : "Активен")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                Spacer()
                RefreshButton(size: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Экран блокировки / Пункт управления (accessory)

private struct AccessoryCircularView: View {
    let entry: BalanceEntry
    var body: some View {
        Gauge(value: 0) { EmptyView() } currentValueLabel: {
            Text(entry.hasData ? shortValue(entry.value) : "—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

private struct AccessoryInlineView: View {
    let entry: BalanceEntry
    var body: some View {
        Label(entry.value, systemImage: "wifi")
    }
}

private struct AccessoryRectangularView: View {
    let entry: BalanceEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(entry.label, systemImage: "wifi")
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            Text(entry.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
            if !entry.updated.isEmpty {
                Text("обновлено \(entry.updated)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// «1 846,03 ₽» → «1 846» - для тесного кружка на локскрине
private func shortValue(_ s: String) -> String {
    let cut = s.split(separator: ",").first.map(String.init) ?? s
    return cut.replacingOccurrences(of: " ₽", with: "")
        .trimmingCharacters(in: .whitespaces)
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BalanceEntry

    // containerBackground обязателен для ВСЕХ семейств (iOS 17+), иначе система
    // рисует заглушку «Please adopt containerBackground API» вместо контента
    var body: some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: AccessoryCircularView(entry: entry)
        case .accessoryInline: AccessoryInlineView(entry: entry)
        case .accessoryRectangular: AccessoryRectangularView(entry: entry)
        case .systemMedium: MediumBalanceView(entry: entry)
        default: SmallBalanceView(entry: entry)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            AccessoryWidgetBackground()
        case .accessoryInline:
            Color.clear
        default:
            WidgetBackground(negative: entry.isNegative && entry.hasData)
        }
    }
}

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "BalanceWidget",
            intent: BalanceWidgetConfig.self,
            provider: BalanceProvider()
        ) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Интерра")
        .description("Баланс или лицевой счёт с быстрым обновлением")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

/// кнопка в Пункте управления (iOS 18): обновить баланс, не открывая приложение
@available(iOS 18.0, *)
struct BalanceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BalanceControl") {
            ControlWidgetButton(action: RefreshBalanceIntent()) {
                Label("Обновить баланс Интерры", systemImage: "wifi")
            }
        }
        .displayName("Баланс Интерры")
        .description("Обновить баланс лицевого счёта")
    }
}

@main
struct InterraWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        if #available(iOS 18.0, *) {
            BalanceControl()
        }
    }
}
