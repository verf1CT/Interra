import UserNotifications

/// Notification Service Extension — скачивает картинку rich-пуша и прикрепляет
/// её к уведомлению, чтобы iOS показал изображение (как Android в трее).
///
/// Работает только если сервер шлёт push с `mutable-content: 1` и URL картинки
/// в `fcm_options.image` — бэкенд ЛК Интерра это уже делает (см. server/src/fcm.js).
class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttempt: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
    guard let content = bestAttempt else {
      contentHandler(request.content)
      return
    }

    // URL картинки FCM кладёт в fcm_options.image (или просто image)
    guard let urlString = imageURL(from: request.content.userInfo),
          let url = URL(string: urlString), urlString.hasPrefix("https://") else {
      contentHandler(content)
      return
    }

    URLSession.shared.downloadTask(with: url) { location, _, _ in
      defer { contentHandler(content) }
      guard let location = location else { return }
      let name = url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try? FileManager.default.removeItem(at: tmp)
      do {
        try FileManager.default.moveItem(at: location, to: tmp)
        let attachment = try UNNotificationAttachment(identifier: "image", url: tmp)
        content.attachments = [attachment]
      } catch {
        // не удалось прикрепить — уведомление всё равно покажется без картинки
      }
    }.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    // время истекло — отдаём то, что успели собрать
    if let handler = contentHandler, let content = bestAttempt {
      handler(content)
    }
  }

  private func imageURL(from userInfo: [AnyHashable: Any]) -> String? {
    if let opts = userInfo["fcm_options"] as? [String: Any],
       let img = opts["image"] as? String {
      return img
    }
    return userInfo["image"] as? String
  }
}
