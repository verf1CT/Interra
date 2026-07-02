import Foundation
import ActivityKit
import Flutter

/// мост Flutter → ActivityKit для Live Activity замера скорости.
/// Канал: `ru.interra/liveactivity`, методы start / update / end
enum LiveActivityBridge {
    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "ru.interra/liveactivity", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            guard #available(iOS 16.2, *) else { result(false); return }
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "start": SpeedActivityManager.start(); result(true)
            case "update": SpeedActivityManager.update(args); result(true)
            case "end": SpeedActivityManager.end(args); result(true)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
}

@available(iOS 16.2, *)
enum SpeedActivityManager {
    private static var activity: Activity<SpeedTestAttributes>?

    private static func state(_ a: [String: Any], finished: Bool)
        -> SpeedTestAttributes.ContentState {
        SpeedTestAttributes.ContentState(
            phase: a["phase"] as? String ?? "",
            download: a["download"] as? Double ?? 0,
            upload: a["upload"] as? Double ?? 0,
            ping: a["ping"] as? Int ?? 0,
            progress: a["progress"] as? Double ?? 0,
            finished: finished)
    }

    static func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // не плодим активности: если предыдущая жива - переиспользуем
        if activity != nil { return }
        let initial = SpeedTestAttributes.ContentState(
            phase: "Подготовка", download: 0, upload: 0, ping: 0,
            progress: 0, finished: false)
        do {
            activity = try Activity.request(
                attributes: SpeedTestAttributes(),
                content: .init(state: initial, staleDate: nil))
        } catch {
            NSLog("LiveActivity start error: \(error)")
        }
    }

    static func update(_ a: [String: Any]) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state(a, finished: false), staleDate: nil)) }
    }

    static func end(_ a: [String: Any]) {
        guard let activity else { return }
        let final = state(a, finished: true)
        Task {
            await activity.end(.init(state: final, staleDate: nil),
                                dismissalPolicy: .after(.now + 4))
        }
        self.activity = nil
    }
}
