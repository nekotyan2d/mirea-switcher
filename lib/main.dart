import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mirea_switcher/data/models/account.dart';
import 'package:mirea_switcher/data/repository/account_repository.dart';
import 'package:mirea_switcher/utils/cookie_utils.dart';
import 'package:mirea_switcher/utils/interceptors.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(App(prefs: prefs));
}

class App extends StatelessWidget {
  final SharedPreferences prefs;
  const App({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color.fromRGBO(22, 119, 255, 1),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromRGBO(245, 245, 245, 1),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color.fromRGBO(22, 119, 255, 1),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromRGBO(29, 29, 29, 1),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(prefs: prefs),
    );
  }
}

class MainScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const MainScreen({super.key, required this.prefs});

  @override
  State<StatefulWidget> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _prefLastAuthToken = 'last_auth_token';

  late final AccountRepository _repo;

  List<Account> _accounts = [];
  String _currentToken = '';
  String _currentUserName = '';
  String _pageTitle = '';
  bool _checkStarted = false;
  bool _cameraGranted = false;
  bool _permissionChecked = false;

  InAppWebViewController? _webViewController;
  late Interceptors _interceptors;

  @override
  void initState() {
    super.initState();

    _repo = AccountRepository(widget.prefs);
    _accounts = _repo.getAll();
    _interceptors = Interceptors(
      onUserName: (name) {
        if (!mounted) return;
        setState(() => _currentUserName = name);
        _onUserNameReceived(name);
      },
      onGetMeIntercepted: () {
        _scheduleHideHeaderForPulse();
        if (!_checkStarted) {
          _checkStarted = true;
          _checkAccounts();
        }
      },
      onUrlChanged: (url) async {
        final controller = _webViewController;
        if (controller == null) return;
        final title = await _interceptors.getTitle(controller);
        _scheduleHideHeaderForPulse();
        if (!mounted) return;
        setState(() => _pageTitle = title?.replaceAll('"', '') ?? '');
      },
    );
    _checkAndRequestPermissions();
  }

  Future<void> _persistLastAuthToken(String token) async {
    if (token.isEmpty) {
      await widget.prefs.remove(_prefLastAuthToken);
    } else {
      await widget.prefs.setString(_prefLastAuthToken, token);
    }
  }

  /// Подставляет куку последней сессии до первого запроса WebView.
  Future<void> _hydrateSessionFromPrefs() async {
    var token = widget.prefs.getString(_prefLastAuthToken);
    if (token == null || token.isEmpty) {
      final all = _repo.getAll();
      if (all.length == 1) token = all.single.token;
    }
    if (token == null || token.isEmpty) return;
    final resolved = token;

    await CookieUtils.setAuthCookie(resolved);
    if (!mounted) return;

    String userName = '';
    for (final a in _repo.getAll()) {
      if (a.token == resolved) {
        userName = a.name;
        break;
      }
    }
    setState(() {
      _currentToken = resolved;
      _currentUserName = userName;
    });
    await _persistLastAuthToken(resolved);
  }

  Future<void> _checkAndRequestPermissions() async {
    await _hydrateSessionFromPrefs();
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _cameraGranted = status.isGranted;
      _permissionChecked = true;
    });
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Требуется разрешение на использование камеры'),
        ),
      );
    }
  }

  void _onUserNameReceived(String name) {
    setState(() {
      _currentUserName = name;
    });
    _repo.addIfAbsent(name, _currentToken);
    setState(() => _accounts = _repo.getAll());
  }

  /// Скрывает шапку сайта; повторы нужны, т.к. после смены сессии React
  /// монтирует хедер позже, чем срабатывает [onLoadStop].
  void _scheduleHideHeaderForPulse() {
    final controller = _webViewController;
    if (controller == null) return;

    Future<void> hide() async {
      if (!mounted) return;
      final c = _webViewController;
      if (c == null) return;
      await _interceptors.hideHeader(c);
    }

    unawaited(hide());
    unawaited(Future.delayed(const Duration(milliseconds: 350), hide));
    unawaited(Future.delayed(const Duration(milliseconds: 900), hide));
    unawaited(Future.delayed(const Duration(milliseconds: 2000), hide));
  }

  void _checkAccounts() async {
    final accountsToCheck = List.of(_accounts);
    for (final account in accountsToCheck) {
      final valid = await _interceptors.checkTokenAsync(
        _webViewController!,
        account.token,
      );
      if (!valid) {
        _repo.remove(account.token);
        if (mounted) setState(() => _accounts = _repo.getAll());
      }
    }

    if (_currentToken.isNotEmpty) {
      await CookieUtils.setAuthCookie(_currentToken);
      await _persistLastAuthToken(_currentToken);
    } else {
      await CookieManager.instance().deleteAllCookies();
      await _persistLastAuthToken('');
    }
  }

  static const _pulseUrl = 'https://pulse.mirea.ru';

  /// После смены куки: на pulse остаёмся на том же URL, иначе открываем корень pulse.
  Future<void> _navigateAfterAccountSwitch() async {
    final c = _webViewController;
    if (c == null) return;
    final u = await c.getUrl();
    final onPulse = u != null && u.host.toLowerCase() == 'pulse.mirea.ru';
    if (onPulse) {
      await c.reload();
    } else {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(_pulseUrl)));
    }
  }

  Future<void> _selectAccount(int index) async {
    if (index == _accounts.length) {
      setState(() {
        _currentToken = '';
        _currentUserName = '';
      });
      await _persistLastAuthToken('');
      await CookieManager.instance().deleteAllCookies();
      _webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(
            'https://attendance.mirea.ru/api/auth/login?redirectUri=https%3A%2F%2Fpulse.mirea.ru%2Fservices&rememberMe=True',
          ),
        ),
      );
    } else {
      final selected = _accounts[index];
      setState(() {
        _currentToken = selected.token;
        _currentUserName = selected.name;
      });
      await CookieUtils.setAuthCookie(_currentToken);
      await _persistLastAuthToken(_currentToken);
      await _navigateAfterAccountSwitch();
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    _interceptors.registerHandlers(controller);
  }

  Future<void> _onLoadStart(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    await _interceptors.hideHeader(controller);
  }

  Future<void> _onLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    _scheduleHideHeaderForPulse();

    final token = await CookieUtils.getAuthToken('https://attendance.mirea.ru');
    if (token != null && token.isNotEmpty) {
      setState(() => _currentToken = token);
      await _persistLastAuthToken(token);
    }
  }

  Future<PermissionResponse> _onPermissionRequest(
    InAppWebViewController controller,
    PermissionRequest request,
  ) async {
    final allowed = request.resources
        .where((r) => r == PermissionResourceType.CAMERA)
        .toList();

    return PermissionResponse(
      resources: allowed,
      action: allowed.isNotEmpty
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          _pageTitle.isEmpty ? 'Mirea Switcher' : _pageTitle,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
        ),
        actions: [
          MenuAnchor(
            builder: (context, controller, child) {
              return TextButton(
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Text(
                  _currentUserName.isEmpty ? 'Войти' : _currentUserName,
                  style: TextStyle(
                    fontWeight: FontWeight.w300,
                    color: Color.fromRGBO(22, 119, 255, 1),
                  ),
                ),
              );
            },
            menuChildren: [
              ..._accounts.asMap().entries.map(
                (e) => MenuItemButton(
                  onPressed: () => _selectAccount(e.key),
                  child: Text(e.value.name),
                ),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.add),
                onPressed: () => _selectAccount(_accounts.length),
                child: const Text('Добавить'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!_permissionChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_cameraGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Требуется разрешение на использование камеры'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAndRequestPermissions,
              child: const Text('Запросить разрешение'),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (await _webViewController?.canGoBack() ?? false) {
          _webViewController?.goBack();
        }
      },
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_pulseUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          overScrollMode: OverScrollMode.NEVER,
        ),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: Interceptors.buildInterceptScript(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          UserScript(
            source: Interceptors.buildHistoryInterceptScript(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final url = navigationAction.request.url;
          if (url != null && url.path.contains('/api/auth/logout')) {
            setState(() {
              _currentToken = '';
              _currentUserName = '';
              _checkStarted = false;
            });
            unawaited(_persistLastAuthToken(''));
          }

          return NavigationActionPolicy.ALLOW;
        },
        onWebViewCreated: _onWebViewCreated,
        onLoadStart: _onLoadStart,
        onLoadStop: _onLoadStop,
        onPermissionRequest: _onPermissionRequest,
      ),
    );
  }
}
