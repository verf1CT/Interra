import AppIntents

/// Интент для Сири и приложения «Команды»: «какой у меня баланс».
/// Пытается получить свежее значение из биллинга, при неудаче отвечает
/// последним сохранённым.
@available(iOS 16.0, *)
struct CheckBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Баланс Интерры"
    static let description =
        IntentDescription("Сообщает баланс лицевого счёта Интерры")
    // Работает без открытия приложения.
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let fresh = await BalanceCore.refresh() {
            return .result(dialog: "Баланс Интерры: \(fresh)")
        }
        if let cached = BalanceCore.cachedText {
            return .result(dialog: "Баланс Интерры: \(cached) (по последним данным)")
        }
        return .result(dialog:
            "Не удалось узнать баланс. Откройте приложение ЛК Интерра.")
    }
}

/// Фразы для Сири. Обязательно содержат название приложения —
/// «Сири, баланс в ЛК Интерра».
@available(iOS 16.0, *)
struct InterraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "Баланс в \(.applicationName)",
                "Какой баланс в \(.applicationName)",
                "\(.applicationName) баланс",
            ],
            shortTitle: "Баланс",
            systemImageName: "creditcard"
        )
    }
}
