import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'cookie_utils.dart';
import 'grpc_web_parser.dart';

class Interceptors {
  final void Function(String name) onUserName;
  final void Function(String token, bool valid) onTokenValidated;
  final void Function(String url) onUrlChanged;

  final Map<String, Completer<bool>> _pendingValidations = {};

  Interceptors({
    required this.onUserName,
    required this.onTokenValidated,
    required this.onUrlChanged,
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
        } catch (e) {
          print('[gRPC] Parse error: $e');
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onGetMeResult',
      callback: (args) {
        final token = args[0] as String;
        final base64 = args[1] as String?;
        final valid = base64 != null &&
            GrpcWebParser.parseFullNameFromBase64(base64) != null;
        _pendingValidations[token]?.complete(valid);
        _pendingValidations.remove(token);
        onTokenValidated(token, valid);
      },
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
  Future <bool> checkTokenAsync(InAppWebViewController controller, String token) {
    final completer = Completer<bool>();
    _pendingValidations[token] = completer;
    checkToken(controller, token);
    return completer.future;
  }
  Future<void> checkToken(InAppWebViewController controller, String token) async {
    await CookieUtils.setAuthCookie(token);

    final script = """
      (function(){
        if (typeof window.__getMe !== 'function') {
          window.flutter_inappwebview.callHandler('onGetMeResult', '$token', null);
          return;
        }
        window.__validating = true;
        window.__getMe()
          .then(function(response) {
            return response.arrayBuffer();
          })
          .then(function(buffer) {
            const bytes = new Uint8Array(buffer);
            window.flutter_inappwebview.callHandler('onGetMeResult', '$token', window.uint8ToBase64(bytes));
          })
          .catch(function(err) {
            console.error('checkToken error:', err);
            window.flutter_inappwebview.callHandler('onGetMeResult', '$token', null);
          }).finally(function() {
            window.__validating = false;
          });
      })();
    """;

    await controller.evaluateJavascript(source: script);
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
      window.__validating = false;

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

      window.__getMe = function() {
        return Promise.reject('getMe not intercepted yet');
      };

      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        const url = (typeof args[0] === 'string' ? args[0] : args[0]?.url) || '';

        if (url.toLowerCase().includes('getme')) {
          window.__getMe = function() {
            return originalFetch.apply(this, args);
          };
          
          if(!window.__validating){
            try {
              const clone = response.clone();
              const buffer = await clone.arrayBuffer();
              const bytes = new Uint8Array(buffer);
              window.flutter_inappwebview.callHandler('onGrpcResponse', url, uint8ToBase64(bytes));
            } catch(e) {
              console.error('Intercept error:', e.message);
            }
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
}