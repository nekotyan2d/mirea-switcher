import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class CookieUtils {
  static final _manager = CookieManager.instance();

  static Map<String, String> parseCookies(String? cookieString) {
    if(cookieString == null || cookieString.trim().isEmpty) return {};

    return Map.fromEntries(
      cookieString.split(';').map((e) => e.trim()).map((e) {
        final parts = e.split('=');
        if(parts.length < 2) return null;
        return MapEntry(parts[0], parts.sublist(1).join('='));
      }).whereType<MapEntry<String, String>>(),
    );
  }

  static Future<void> setAuthCookie(String token) async {
    await _manager.setCookie(
      url: WebUri('https://pulse.mirea.ru'),
      name: '.AspNetCore.Cookies',
      value: token,
      domain: '.mirea.ru',
      path: '/',
      sameSite: HTTPCookieSameSitePolicy.NONE,
      isSecure: true,
    );
  }
  
  static Future<String?> getAuthToken(String domain) async {
    final cookie = await _manager.getCookie(
        url: WebUri(domain),
        name: '.AspNetCore.Cookies'
    );
    return cookie?.value;
  }
}