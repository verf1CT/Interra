/// Конфигурация приложения «ЛК Интерра».
class AppConfig {
  /// Адрес веб-кабинета провайдера (UTM5), который показываем в WebView.
  static const String portalUrl = 'https://stat.interra.ru/';

  /// Страница входа по паролю (форма с полями user/pass).
  static const String loginUrl =
      'https://stat.interra.ru/cgi-bin/utm5/aaa?login=&oper=ident';

  /// Базовый адрес нашего бэкенда (server/). ЗАМЕНИТЬ на реальный домен/IP.
  /// Для локальной отладки на эмуляторе Android используйте http://10.0.2.2:8080
  static const String backendBaseUrl = 'https://push.interra.ru';

  /// Версия приложения, передаётся при регистрации устройства.
  static const String appVersion = '0.1.0';
}
