import Flutter
import UIKit
import AppIntents
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// идентификатор фоновой задачи обновления баланса (должен совпадать с
  /// BGTaskSchedulerPermittedIdentifiers в Info.plist)
  private let refreshTaskId = "ru.interra.balance.refresh"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WatchSync.shared.start()
    // форсируем регистрацию фраз Сири (App Shortcuts) при каждом запуске -
    // иначе система может не подхватить их после установки
    if #available(iOS 16.0, *) {
      InterraShortcuts.updateAppShortcutParameters()
    }
    registerBackgroundRefresh()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    // уход в фон - удобный момент отдать часам свежий баланс
    WatchSync.shared.push()
    super.applicationWillResignActive(application)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    scheduleBackgroundRefresh()
    super.applicationDidEnterBackground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Фоновое обновление баланса (BGTaskScheduler)

  private func registerBackgroundRefresh() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: refreshTaskId, using: nil
    ) { [weak self] task in
      self?.handleBackgroundRefresh(task as! BGAppRefreshTask)
    }
  }

  /// планирует следующий запуск не раньше чем через ~4 часа (систему решает,
  /// когда именно, исходя из энергоэффективности и паттерна использования)
  private func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
    try? BGTaskScheduler.shared.submit(request)
  }

  private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    // сразу ставим следующую задачу в очередь, чтобы цепочка не прерывалась
    scheduleBackgroundRefresh()

    let work = Task {
      _ = await BalanceCore.refresh() // обновит app group и перерисует виджет
      WatchSync.shared.push()         // и синхронизируем часы
      task.setTaskCompleted(success: true)
    }
    // если система прерывает задачу (лимит времени) - отменяем работу
    task.expirationHandler = { work.cancel() }
  }
}
