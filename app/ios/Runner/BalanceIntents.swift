import AppIntents

/// интент для Сири и приложения «Команды»: «какой у меня баланс».
/// Пытается получить свежее значение из биллинга, при неудаче отвечает
/// последним сохранённым
@available(iOS 16.0, *)
struct CheckBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Баланс Интерры"
    static let description =
        IntentDescription("Сообщает баланс лицевого счёта Интерры")
    // работает без открытия приложения
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // сири жёстко ограничивает время выполнения интента, поэтому отвечаем
        // МГНОВЕННО сохранённым балансом (пишется при каждом открытии приложения
        // и обновлении виджета), а свежий подтягиваем в фоне для следующего раза
        if let cached = BalanceCore.cachedText {
            Task.detached { _ = await BalanceCore.refresh() }
            return .result(dialog: "Баланс Интерры: \(cached)")
        }
        // кэша ещё нет - пробуем сеть (с коротким таймаутом внутри)
        if let fresh = await BalanceCore.refresh() {
            return .result(dialog: "Баланс Интерры: \(fresh)")
        }
        return .result(dialog:
            "Не удалось узнать баланс. Откройте приложение ЛК Интерра.")
    }
}

/// фразы для Сири. обязательно содержат название приложения -
/// «Сири, баланс в ЛК Интерра»
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
