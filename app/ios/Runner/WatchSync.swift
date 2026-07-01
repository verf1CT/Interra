import Foundation
import WatchConnectivity

/// Синхронизация с Apple Watch: отправляет на часы баланс и токен биллинга
/// (из app group, куда их пишет Dart-слой) через applicationContext —
/// доставится даже когда часы не рядом (при следующем контакте).
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Публикует текущие данные на часы. Вызывать при уходе в фон и после
    /// активации сессии. Повтор одинакового контекста система сама глотает.
    func push() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        let d = UserDefaults(suiteName: BalanceCore.appGroup)
        // Отправляем ВСЕ ключи (пустая строка, если значения нет), чтобы часы
        // могли и очиститься после выхода из аккаунта, а не только получить
        // обновление. applicationContext перезаписывает предыдущий целиком.
        var ctx: [String: Any] = [:]
        for key in ["balance_text", "balance_updated", "bbb_token"] {
            ctx[key] = d?.string(forKey: key) ?? ""
        }
        try? session.updateApplicationContext(ctx)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Часы могут запросить данные явно (messages) — отдаём то же самое.
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let d = UserDefaults(suiteName: BalanceCore.appGroup)
        var reply: [String: Any] = [:]
        for key in ["balance_text", "balance_updated", "bbb_token"] {
            if let v = d?.string(forKey: key) { reply[key] = v }
        }
        replyHandler(reply)
    }
}
