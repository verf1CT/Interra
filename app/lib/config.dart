/// конфигурация приложения «ЛК Интерра»
class AppConfig {
  /// адрес веб-кабинета провайдера (UTM5) - на случай открытия портала напрямую
  static const String portalUrl = 'https://stat.interra.ru/';

  /// базовый путь CGI-скриптов биллинга UTM5
  static const String billingBase = 'https://stat.interra.ru/cgi-bin/utm5';

  /// эндпоинт `bbb` - регистрация приложения и получение ссылки на ЛК
  static const String bbbUrl = '$billingBase/bbb';

  /// полный адрес кабинета из ответа `cmd=open` (ответ вида `?login=X.123…`).
  ///
  /// Грузим именно `aaainfo…&oper=info` (страница «Основная информация»):
  /// `aaa…` отдаёт лишь оболочку с пустым телом, а контент (баланс, тариф)
  /// рендерит `aaainfo`. параметр `loginParam` уже начинается с `?login=`
  static String cabinetFromLoginParam(String loginParam) =>
      '$billingBase/aaainfo$loginParam&oper=info';

  /// базовый адрес нашего бэкенда (server/) для push-рассылок.
  /// Для локальной отладки на эмуляторе Android: http://10.0.2.2:8080
  static const String backendBaseUrl = 'https://push.interra.ru';

  /// версия приложения, передаётся при регистрации устройства
  static const String appVersion = '1.0.0';

  // --- контакты поддержки (экран «Поддержка», быстрые действия) ---------------
  // Источник: официальный сайт interra.ru. если контакты изменятся - правим тут.

  /// Единый телефон контактного центра (только цифры - для набора)
  static const String supportPhone = '88007700010';

  /// тот же телефон в человекочитаемом виде - для показа в интерфейсе
  static const String supportPhoneHuman = '8 800 770-00-10';

  /// новостной канал в Telegram (это канал, писать в него нельзя)
  static const String supportTelegram = 'tginterra';

  /// сообщество ВКонтакте
  static const String supportVkUrl = 'https://vk.com/public172258204';

  /// раздел помощи на сайте провайдера
  static const String supportHelpUrl = 'https://interra.ru/help/';
}
