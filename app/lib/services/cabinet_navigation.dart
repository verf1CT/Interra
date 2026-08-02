import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class CabinetNavigation {
  /// свой хост держим внутри WebView, всё остальное - наружу
  static const String host = 'stat.interra.ru';

  /// внешние ссылки (`tel:`, `mailto:`, чужие домены с target=_blank)
  /// открываем в системных приложениях, не внутри WebView
  static NavigationDecision handleNavigationRequest(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.navigate;
    final scheme = uri.scheme.toLowerCase();

    if (scheme == 'tel' || scheme == 'mailto' || scheme == 'sms') {
      _launchExternal(uri);
      return NavigationDecision.prevent;
    }
    if ((scheme == 'http' || scheme == 'https') && uri.host != host) {
      _launchExternal(uri);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  static Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть $uri: $e');
    }
  }
}
