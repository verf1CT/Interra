import ActivityKit

/// Состояние Live Activity замера скорости. Общий тип для приложения (запускает
/// и обновляет активность) и виджет-расширения (рисует её).
@available(iOS 16.1, *)
struct SpeedTestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// «Пинг» / «Загрузка» / «Отдача» / «Готово».
        var phase: String
        var download: Double
        var upload: Double
        var ping: Int
        /// 0…1 — прогресс текущего этапа.
        var progress: Double
        var finished: Bool
    }
}
