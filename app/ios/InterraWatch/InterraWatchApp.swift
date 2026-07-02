import SwiftUI
import WatchConnectivity

/// приложение «Интерра» для Apple Watch: баланс на запястье.
///
/// Данные (баланс + токен биллинга) приходят с телефона через
/// WatchConnectivity (applicationContext) и кэшируются в UserDefaults часов.
/// Кнопка обновления запрашивает баланс напрямую из биллинга через
/// [BalanceCore] - часы умеют в сеть сами (через телефон или Wi-Fi)
@main
struct InterraWatchApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var balance = "—"
    @Published var updated = ""

    override init() {
        super.init()
        load()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func load() {
        let d = BalanceCore.defaults
        let b = d?.string(forKey: "balance_text") ?? ""
        balance = b.isEmpty ? "—" : b
        updated = d?.string(forKey: "balance_updated") ?? ""
    }

    @MainActor
    func refresh() async {
        if await BalanceCore.refresh() != nil { load() }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ ctx: [String: Any]) {
        guard !ctx.isEmpty else { return }
        let d = BalanceCore.defaults
        for key in ["balance_text", "balance_updated", "bbb_token"] {
            if let v = ctx[key] as? String { d?.set(v, forKey: key) }
        }
        DispatchQueue.main.async { self.load() }
    }
}

struct ContentView: View {
    @StateObject private var model = WatchModel()
    @State private var busy = false

    private let brand = Color(red: 0x3C / 255, green: 0x98 / 255, blue: 0xD4 / 255)
    private let accent = Color(red: 0xF4 / 255, green: 0x75 / 255, blue: 0x2D / 255)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .bold))
                Text("Интерра")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(brand)

            Spacer()

            Text(model.balance)
                .font(.system(size: 30, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(accent)

            Text(model.updated.isEmpty ? "Баланс" : "Баланс · \(model.updated)")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                Task {
                    busy = true
                    await model.refresh()
                    busy = false
                }
            } label: {
                if busy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(busy)
        }
        .padding()
    }
}
