import Flutter
import UIKit
import AppIntents

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WatchSync.shared.start()
    // Форсируем регистрацию фраз Сири (App Shortcuts) при каждом запуске —
    // иначе система может не подхватить их после установки.
    if #available(iOS 16.0, *) {
      InterraShortcuts.updateAppShortcutParameters()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    // Уход в фон — удобный момент отдать часам свежий баланс.
    WatchSync.shared.push()
    super.applicationWillResignActive(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InterraLiveActivity") {
      LiveActivityBridge.register(messenger: registrar.messenger())
    }
  }
}
