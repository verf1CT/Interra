/// Конфигурация приложения «ЛК Интерра».
class AppConfig {
  /// Адрес веб-кабинета провайдера (UTM5) — на случай открытия портала напрямую.
  static const String portalUrl = 'https://stat.interra.ru/';

  /// Базовый путь CGI-скриптов биллинга UTM5.
  static const String billingBase = 'https://stat.interra.ru/cgi-bin/utm5';

  /// Эндпоинт `bbb` — регистрация приложения и получение ссылки на ЛК.
  static const String bbbUrl = '$billingBase/bbb';

  /// Полный адрес кабинета из ответа `cmd=open` (ответ вида `?login=X.123…`).
  ///
  /// Грузим именно `aaainfo…&oper=info` (страница «Основная информация»):
  /// `aaa…` отдаёт лишь оболочку с пустым телом, а контент (баланс, тариф)
  /// рендерит `aaainfo`. Параметр `loginParam` уже начинается с `?login=`.
  static String cabinetFromLoginParam(String loginParam) =>
      '$billingBase/aaainfo$loginParam&oper=info';

  /// Базовый адрес нашего бэкенда (server/) для push-рассылок.
  /// Для локальной отладки на эмуляторе Android: http://10.0.2.2:8080
  static const String backendBaseUrl = 'https://push.interra.ru';

  /// Версия приложения, передаётся при регистрации устройства.
  static const String appVersion = '0.1.0';

  // --- Контакты поддержки (экран «Поддержка», быстрые действия) ---------------
  // Источник: официальный сайт interra.ru. Если контакты изменятся — правим тут.

  /// Единый телефон контактного центра (только цифры — для набора).
  static const String supportPhone = '88007700010';

  /// Тот же телефон в человекочитаемом виде — для показа в интерфейсе.
  static const String supportPhoneHuman = '8 800 770-00-10';

  /// Канал поддержки в Telegram.
  static const String supportTelegram = 'tginterra';

  /// Сообщество ВКонтакте.
  static const String supportVkUrl = 'https://vk.com/public172258204';

  /// Раздел помощи на сайте провайдера.
  static const String supportHelpUrl = 'https://interra.ru/help/';
}
