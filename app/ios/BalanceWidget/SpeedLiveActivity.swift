import ActivityKit
import WidgetKit
import SwiftUI

/// live Activity замера скорости: плашка на экране блокировки и в Dynamic Island
@available(iOS 16.2, *)
struct SpeedLiveActivity: Widget {
    private var brand: Color { Color(red: 0x3C / 255, green: 0x98 / 255, blue: 0xD4 / 255) }
    private var accent: Color { Color(red: 0xF4 / 255, green: 0x75 / 255, blue: 0x2D / 255) }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeedTestAttributes.self) { context in
            // экран блокировки / баннер
            lockScreen(context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Интерра", systemImage: "wifi").font(.caption).foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase).font(.caption).foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expanded(context.state)
                }
            } compactLeading: {
                Image(systemName: "speedometer").foregroundColor(brand)
            } compactTrailing: {
                Text(mbps(context.state.download))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            } minimal: {
                Image(systemName: "speedometer").foregroundColor(brand)
            }
            .widgetURL(URL(string: "interra://speedtest"))
        }
    }

    @ViewBuilder
    private func lockScreen(_ s: SpeedTestAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Проверка скорости", systemImage: "speedometer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(s.finished ? "Готово" : s.phase)
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 18) {
                metric("Загрузка", mbps(s.download), accent)
                metric("Отдача", mbps(s.upload), brand)
                metric("Пинг", s.ping > 0 ? "\(s.ping)" : "—", .white)
            }
            if !s.finished {
                ProgressView(value: s.progress)
                    .tint(accent)
            }
        }
    }

    @ViewBuilder
    private func expanded(_ s: SpeedTestAttributes.ContentState) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                metric("Загрузка", mbps(s.download), accent)
                metric("Отдача", mbps(s.upload), brand)
                metric("Пинг", s.ping > 0 ? "\(s.ping)" : "—", .white)
            }
            if !s.finished { ProgressView(value: s.progress).tint(accent) }
        }
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    private func mbps(_ v: Double) -> String {
        v <= 0 ? "—" : (v >= 100 ? "\(Int(v))" : String(format: "%.1f", v))
    }
}
