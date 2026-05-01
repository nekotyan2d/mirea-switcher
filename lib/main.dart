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
            brightness: Brightness.light
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromRGBO(245, 245, 245, 1),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Color.fromRGBO(22, 119, 255, 1),
              brightness: Brightness.dark
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color.fromRGBO(29, 29, 29, 1),
          ),
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(prefs: prefs)
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
  late final AccountRepository _repo;

  List<Account> _accounts = [];
  String _currentToken = '';
  String _currentUserName = '';
  String _pageTitle = '';
  final Set<String> _validatedTokens = {};
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
        onUserName: (name){
          if(!mounted) return;
          setState(() => _currentUserName = name);
          _onUserNameReceived(name);
        },
        onTokenValidated: (token, valid) {
          if (!mounted) return;
          print("token validated: $token, $valid");
          setState(() => _onTokenValidated(token, valid));
        },
        onUrlChanged: (url) async {
          final controller = _webViewController;
          if (controller == null) return;
          final title = await _interceptors.getTitle(controller);
          await _interceptors.hideHeader(controller);
          if (!mounted) return;
          setState(() => _pageTitle = title?.replaceAll('"', '') ?? '');
        },
    );
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _cameraGranted = status.isGranted;
      _permissionChecked = true;
    });
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Требуется разрешение на использование камеры')),
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

  void _checkAccounts() async {
    final accountsToCheck = List.of(_accounts);
    for (final account in accountsToCheck) {
      final valid = await _interceptors.checkTokenAsync(
          _webViewController!,
          account.token
      );

      if(!valid) {
        _repo.remove(account.token);
        if(mounted) setState(() => _accounts = _repo.getAll());
      }
    }

    if(_currentToken.isNotEmpty) {
      await CookieUtils.setAuthCookie(_currentToken);
    }else{
      await CookieManager.instance().deleteAllCookies();
    }
  }

  void _onTokenValidated(String token, bool valid) {
    if (!valid) _repo.remove(token);
    _accounts = _repo.getAll();
  }

  Future<void> _selectAccount(int index) async {
    if (index == _accounts.length) {
      setState(() {
        _currentToken = '';
        _currentUserName = '';
      });
      await CookieManager.instance().deleteAllCookies();
    } else {
      final selected = _accounts[index];
      _currentToken = selected.token;
      await CookieUtils.setAuthCookie(_currentToken);
    }
    _webViewController?.reload();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    _interceptors.registerHandlers(controller);
  }

  Future<void> _onLoadStart(InAppWebViewController controller, WebUri? url) async {
    await _interceptors.hideHeader(controller);
  }

  Future<void> _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    await _interceptors.hideHeader(controller);

    final token = await CookieUtils.getAuthToken('https://attendance.mirea.ru');
    if (token != null && token.isNotEmpty) {
      setState(() => _currentToken = token);
    }

    if (!_checkStarted) {
      _checkStarted = true;
      _checkAccounts();
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
        titleSpacing: 16,
        title: Text(
          _pageTitle.isEmpty ? 'Mirea Switcher' : _pageTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold
          ),
          overflow: TextOverflow.ellipsis,
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
                    color: Color.fromRGBO(22, 119, 255, 1)
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
      body: SafeArea(
        child: _buildBody(),
      ),
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
        initialUrlRequest: URLRequest(url: WebUri('https://pulse.mirea.ru')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
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
        onWebViewCreated: _onWebViewCreated,
        onLoadStart: _onLoadStart,
        onLoadStop: _onLoadStop,
        onPermissionRequest: _onPermissionRequest,
      ),
    );
  }
}

