import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Genera PO Token (proof-of-origin) con una WebView nascosta che esegue
/// il BotGuard di YouTube: è l'unico modo per sbloccare gli stream completi
/// per i client web (stessa strada di yt-dlp + bgutil-ytdlp-pot-provider).
///
/// Il bundle JS (assets/pot_bundle.js) espone `window.__bgGenPot(binding)`.
/// NB: evaluateJavascript su iOS NON risolve le Promise, quindi il risultato
/// torna tramite il bridge `callHandler('potResult', ...)`.
class PotService {
  bool _starting = false;
  Completer<void>? _ready;
  HeadlessInAppWebView? _webview;

  /// Ultimo errore verificatosi (per la diagnostica).
  String? lastError;

  final Map<String, (String, DateTime)> _cache = {};
  final Map<String, Completer<String>> _pending = {};
  static const _ttl = Duration(hours: 5);

  bool get isReady => _ready?.isCompleted == true && !_starting;

  /// Avvia la webview nascosta e inietta il bundle (idempotente).
  Future<void> start() async {
    if (_starting) {
      await (_ready?.future ?? Future.value()).catchError((_) {});
      return;
    }
    _starting = true;
    _ready = Completer<void>();
    try {
      final bundle = await rootBundle.loadString('assets/pot_bundle.js');
      final webview = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('https://www.youtube.com/')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: true,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, uri) async {
          // Se YouTube ci manda sulla pagina di consenso cookie (tipico
          // nell'UE), torniamo all'homepage con il bypass del consenso.
          final host = uri?.host ?? '';
          if (!host.contains('youtube.com')) {
            developer.log('POT redirect da $host → homepage con ucbcb=1');
            await controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri('https://www.youtube.com/?ucbcb=1&hl=it'),
              ),
            );
            return;
          }
          try {
            // Bridge: il JS consegna il token via callHandler perché
            // le Promise di evaluateJavascript non sono attendibili su iOS.
            controller.addJavaScriptHandler(
              handlerName: 'potResult',
              callback: (args) {
                if (args.length >= 2) {
                  final binding = args[0] as String;
                  final err = args[1] as String?;
                  final token = args.length > 2 ? args[2] as String? : null;
                  final c = _pending.remove(binding);
                  if (c != null && !c.isCompleted) {
                    if (err != null || token == null || token.isEmpty) {
                      lastError = err ?? 'token vuoto';
                      c.completeError(Exception(lastError));
                    } else {
                      _cache[binding] = (token, DateTime.now().add(_ttl));
                      c.complete(token);
                    }
                  }
                }
                return null;
              },
            );
            await controller.evaluateJavascript(source: bundle);
            developer.log('POT bundle iniettato');
            await controller.evaluateJavascript(
              source: "window.__bgWarmup ? window.__bgWarmup() : false",
            );
            developer.log('POT webview pronta');
            if (!_ready!.isCompleted) _ready!.complete();
          } catch (e) {
            lastError = 'inject: $e';
            developer.log('POT inject errore: $e');
            if (!_ready!.isCompleted) _ready!.completeError(e);
          }
        },
        onConsoleMessage: (controller, msg) {
          developer.log('POT console[${msg.messageLevel}]: ${msg.message}');
        },
      );
      await webview.run();
      _webview = webview;
    } catch (e) {
      lastError = 'start: $e';
      developer.log('POT start errore: $e');
      if (!_ready!.isCompleted) _ready!.completeError(e);
    } finally {
      _starting = false;
    }
    await _ready!.future.catchError((_) {});
  }

  /// PO token per [contentBinding] (visitorData per il player, videoId
  /// per i media URL). Ritorna null se non disponibile.
  Future<String?> generatePot(String contentBinding) async {
    try {
      final cached = _cache[contentBinding];
      if (cached != null && DateTime.now().isBefore(cached.$2)) {
        return cached.$1;
      }
      final existing = _pending[contentBinding];
      if (existing != null) return await existing.future;

      await start();
      final controller = _webview?.webViewController;
      if (controller == null) {
        lastError = 'webview non disponibile';
        return null;
      }

      final c = Completer<String>();
      _pending[contentBinding] = c;
      final escaped = jsonEncode(contentBinding);

      // Fire-and-forget: il risultato arriva dal bridge potResult.
      unawaited(
        controller.evaluateJavascript(
          source:
              '''
        (function(){
          try {
            window.__bgGenPot($escaped)
              .then(function(t){
                window.flutter_inappwebview.callHandler('potResult', $escaped, null, t);
              })
              .catch(function(e){
                window.flutter_inappwebview.callHandler('potResult', $escaped, String(e), null);
              });
          } catch(e) {
            window.flutter_inappwebview.callHandler('potResult', $escaped, String(e), null);
          }
        })();
      ''',
        ),
      );

      final token = await c.future.timeout(const Duration(seconds: 60));
      developer.log('POT ok (${token.length} char)');
      return token;
    } catch (e) {
      lastError = 'generatePot: $e';
      developer.log('POT generatePot errore: $e');
      return null;
    } finally {
      _pending.remove(contentBinding);
    }
  }

  String? _cachedWebVd;
  DateTime? _webVdAt;

  /// VisitorData DELLA WEBVIEW: i token sono legati a questa sessione,
  /// quindi le richieste player devono usare lo stesso valore. Cache ~6h:
  /// senza, ogni resolve farebbe un round-trip JS.
  Future<String?> webVisitorData() async {
    if (_cachedWebVd != null &&
        _webVdAt != null &&
        DateTime.now().difference(_webVdAt!) < const Duration(hours: 6)) {
      return _cachedWebVd;
    }
    try {
      await start();
      final controller = _webview?.webViewController;
      if (controller == null) return null;
      final r = await controller
          .evaluateJavascript(
            source:
                "(window.ytcfg && window.ytcfg.get) ? window.ytcfg.get('VISITOR_DATA') : null",
          )
          .timeout(const Duration(seconds: 15));
      if (r == null || r == 'null' || r.toString().isEmpty) {
        lastError = 'visitorData webview assente';
        return null;
      }
      _cachedWebVd = r.toString();
      _webVdAt = DateTime.now();
      return _cachedWebVd;
    } catch (e) {
      lastError = 'webVisitorData: $e';
      return null;
    }
  }

  void dispose() {
    _webview?.dispose();
    _webview = null;
  }
}
