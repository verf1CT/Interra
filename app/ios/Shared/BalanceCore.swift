import Foundation
import WidgetKit

/// Общий нативный код баланса — используется и приложением (интент Сири),
/// и виджетом (кнопка «Обновить»). Дублирует минимум логики Dart-слоя:
/// bbb cmd=open → aaainfo → регулярка «Баланс … руб.».
enum BalanceCore {
    static let appGroup = "group.ru.interra.lkInterra"
    static let widgetKind = "BalanceWidget"
    static let billingBase = "https://stat.interra.ru/cgi-bin/utm5"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Сессия с коротким таймаутом: интенты Сири и обновление виджета жёстко
    /// ограничены по времени, дефолтные 60 сек URLSession недопустимы.
    private static var session: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    /// Последний сохранённый баланс («1 846,03 ₽») или nil.
    static var cachedText: String? {
        let t = defaults?.string(forKey: "balance_text")
        return (t == nil || t == "—" || t!.isEmpty) ? nil : t
    }

    /// Свежий баланс из биллинга. Токен приложения зеркалируется Dart-слоем
    /// в app group (доступен только нашим подписанным приложениям).
    static func fetchFresh() async -> Double? {
        guard let token = defaults?.string(forKey: "bbb_token"), !token.isEmpty,
              let openURL = URL(string: "\(billingBase)/bbb?cmd=open&app=\(token)")
        else { return nil }
        do {
            let (d1, _) = try await session.data(from: openURL)
            var login = String(data: d1, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            login = login.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard login.hasPrefix("?login="),
                  let infoURL = URL(string: "\(billingBase)/aaainfo\(login)&oper=info")
            else { return nil }

            let (d2, _) = try await session.data(from: infoURL)
            guard let html = String(data: d2, encoding: .utf8) else { return nil }
            // «…Баланс…1846.03 руб.» — ищем число перед «руб» после слова Баланс.
            // Внимание: в шаблоне ICU неразрывный пробел —   (ровно 4 hex),
            // НЕ swift-синтаксис \u{00a0}, иначе регулярка не компилируется.
            let re = try NSRegularExpression(
                pattern: "Баланс[\\s\\S]{0,200}?(-?[\\d\\u00a0 ]+(?:[.,]\\d+)?)\\s*руб",
                options: [])
            let range = NSRange(html.startIndex..., in: html)
            guard let m = re.firstMatch(in: html, options: [], range: range),
                  let r = Range(m.range(at: 1), in: html) else { return nil }
            let raw = html[r]
                .replacingOccurrences(of: "\u{00a0}", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
            return Double(raw)
        } catch {
            return nil
        }
    }

    /// «1 846,03 ₽» — формат как в приложении (BalanceStore.format).
    static func format(_ amount: Double) -> String {
        let sign = amount < 0 ? "\u{2212}" : ""
        let abs = Swift.abs(amount)
        let whole = Int(abs)
        let cents = Int(((abs - Double(whole)) * 100).rounded())
        var digits = String(whole)
        var grouped = ""
        while digits.count > 3 {
            grouped = " " + String(digits.suffix(3)) + grouped
            digits = String(digits.dropLast(3))
        }
        grouped = digits + grouped
        let frac = cents == 0 ? "" : String(format: ",%02d", cents)
        return "\(sign)\(grouped)\(frac) ₽"
    }

    /// Сохраняет свежее значение для виджета/Сири и перерисовывает виджет.
    static func store(_ amount: Double) {
        let d = defaults
        d?.set(format(amount), forKey: "balance_text")
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        d?.set(f.string(from: Date()), forKey: "balance_updated")
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Обновить и вернуть текст баланса (для интентов). nil — не получилось.
    @discardableResult
    static func refresh() async -> String? {
        guard let amount = await fetchFresh() else { return nil }
        store(amount)
        return format(amount)
    }
}
