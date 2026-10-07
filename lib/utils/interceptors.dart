import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'grpc_web_parser.dart';

class Interceptors {
  final void Function(String name) onUserName;
  final void Function() onGetMeIntercepted;
  final void Function(String url) onUrlChanged;
  final void Function() onOpenAccounts;

  Interceptors({
    required this.onUserName,
    required this.onGetMeIntercepted,
    required this.onUrlChanged,
    required this.onOpenAccounts,
  });

  void registerHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onGrpcResponse',
      callback: (args) {
        try {
          final url = args[0] as String;
          final base64Body = args[1] as String;
          final name = GrpcWebParser.parseFullNameFromBase64(base64Body);
          if (name != null) onUserName(name);
          onGetMeIntercepted();
        } catch (e) {
          print('[gRPC] Parse error: $e');
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'openAccounts',
      callback: (_) => onOpenAccounts(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'onUrlChange',
      callback: (args) {
        final url = args[0] as String;
        Future.delayed(const Duration(milliseconds: 300), () {
          onUrlChanged(url);
        });
      },
    );
  }
  Future<String?> getTitle(InAppWebViewController controller) async {
    final result = await controller.evaluateJavascript(source: "document.title ?? ''");
    return result?.toString();
  }

  Future<void> hideHeader(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: """
      document.querySelectorAll('.ant-flex.ant-flex-align-center.ant-flex-justify-space-between').forEach(item => {
        if(item.parentElement.className.includes('root')) item.style.display = 'none';
      });
    """);
  }

  static String buildInterceptScript() => """
    (function() {
      if (window.__grpcIntercepted) return;
      window.__grpcIntercepted = true;

      window.uint8ToBase64 = (bytes) => {
        let binary = '';
        const chunkSize = 8192;
        for (let i = 0; i < bytes.length; i += chunkSize) {
          const chunk = bytes.subarray(i, i + chunkSize);
          for (let j = 0; j < chunk.length; j++) {
            binary += String.fromCharCode(chunk[j]);
          }
        }
        return btoa(binary);
      }

      const originalFetch = window.fetch;

      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        const url = (typeof args[0] === 'string' ? args[0] : args[0]?.url) || '';

        if (url.toLowerCase().includes('getme')) {
          try {
            const clone = response.clone();
            const buffer = await clone.arrayBuffer();
            const bytes = new Uint8Array(buffer);
            window.flutter_inappwebview.callHandler('onGrpcResponse', url, uint8ToBase64(bytes));
          } catch(e) {
            console.error('Intercept error:', e.message);
          }
        }
        return response;
      };
    })();
  """;

  static String buildHistoryInterceptScript() => """
    (function() {
      if (window.__historyIntercepted) return;
      window.__historyIntercepted = true;

      const originalPushState = history.pushState;
      const originalReplaceState = history.replaceState;

      function onUrlChanged() {
        window.flutter_inappwebview.callHandler('onUrlChange', window.location.href);
      }

      history.pushState = function(...args) {
        originalPushState.apply(this, args);
        onUrlChanged();
      };

      history.replaceState = function(...args) {
        originalReplaceState.apply(this, args);
        onUrlChanged();
      };

      window.addEventListener('popstate', onUrlChanged);
    })();
  """;

  /// Вставляет кнопку «Аккаунты» в группу настроек, клонируя соседнюю
  /// кнопку, чтобы взять актуальные (хешированные) классы сайта.
  static String buildAccountsButtonScript() => """
    (function() {
      if (window.__accountsBtnObserver) return;
      const userPath = 'M858.5 763.6a374 374 0 00-80.6-119.5 375.63 375.63 0 00-119.5-80.6c-.4-.2-.8-.3-1.2-.5C719.5 518 760 444.7 760 362c0-137-111-248-248-248S264 225 264 362c0 82.7 40.5 156 102.8 201.1-.4.2-.8.3-1.2.5-44.8 18.9-85 46-119.5 80.6a375.63 375.63 0 00-80.6 119.5A371.7 371.7 0 00136 901.8a8 8 0 008 8.2h60c4.4 0 7.9-3.5 8-7.8 2-77.2 33-149.5 87.8-204.3 56.7-56.7 132-87.9 212.2-87.9s155.5 31.2 212.2 87.9C779 752.7 810 825 812 902.2c.1 4.4 3.6 7.8 8 7.8h60a8 8 0 008-8.2c-1-47.8-10.9-94.3-29.5-138.2zM512 534c-45.9 0-89.1-17.9-121.6-50.4S340 407.9 340 362c0-45.9 17.9-89.1 50.4-121.6S466.1 190 512 190s89.1 17.9 121.6 50.4S684 316.1 684 362c0 45.9-17.9 89.1-50.4 121.6S557.9 534 512 534z';

      function inject() {
        if (location.pathname !== '/settings') return;
        const src = Array.from(document.querySelectorAll('button'))
          .find(b => b.textContent.includes('История изменений'));
        if (!src || !src.parentElement) return;
        if (src.parentElement.querySelector('[data-accounts-btn]')) return;

        const btn = src.cloneNode(true);
        btn.setAttribute('data-accounts-btn', '1');
        btn.classList.forEach(c => { if (c.startsWith('_first_')) btn.classList.remove(c); });
        const path = btn.querySelector('.ant-btn-icon svg path');
        if (path) path.setAttribute('d', userPath);
        const label = Array.from(btn.children).find(c => !c.className);
        if (label) label.textContent = 'Аккаунты';
        btn.addEventListener('click', () => {
          window.flutter_inappwebview.callHandler('openAccounts');
        });
        src.after(btn);
      }

      window.__accountsBtnObserver = new MutationObserver(inject);
      window.__accountsBtnObserver.observe(document.documentElement, {childList: true, subtree: true});
    })();
  """;
}
