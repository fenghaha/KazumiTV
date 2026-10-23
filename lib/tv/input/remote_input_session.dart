import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:kazumi/tv/input/tv_input_limits.dart';
import 'package:kazumi/tv/input/tv_lan_address.dart';

/// One short-lived phone editor. No server, address or failed startup survives
/// its dialog. The capability is random, never persisted and revoked on close.
class RemoteInputSession {
  RemoteInputSession._({
    required HttpServer server,
    required String token,
    required this.title,
    required this.initialText,
    required this.obscureText,
    required this.maxLength,
    required bool Function(String text, bool submit) onInput,
    required Duration lifetime,
  }) : _server = server,
       _token = token,
       _onInput = onInput {
    _subscription = _server.listen(_handleRequest);
    _expiry = Timer(lifetime, close);
  }

  final HttpServer _server;
  final String _token;
  final String title;
  final String initialText;
  final bool obscureText;
  final int maxLength;
  final bool Function(String text, bool submit) _onInput;
  final _submitted = StreamController<void>.broadcast();
  late final StreamSubscription<HttpRequest> _subscription;
  late final Timer _expiry;
  bool _closed = false;

  Uri get url => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/$_token',
  );
  Stream<void> get submitted => _submitted.stream;
  bool get isClosed => _closed;

  static Future<RemoteInputSession> start({
    required String title,
    required String initialText,
    required bool Function(String text, bool submit) onInput,
    bool obscureText = false,
    int maxLength = 4096,
    Duration lifetime = const Duration(minutes: 10),
    Future<InternetAddress?> Function()? addressProvider,
  }) async {
    final address = await (addressProvider ?? _lanAddress)();
    if (address == null) {
      throw const SocketException('No local network address');
    }
    // Bind the selected LAN interface rather than exposing all interfaces.
    final server = await HttpServer.bind(address, 0);
    final random = Random.secure();
    final token = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return RemoteInputSession._(
      server: server,
      token: token,
      title: title,
      initialText: obscureText ? '' : initialText,
      obscureText: obscureText,
      maxLength: TvInputLimits.normalize(maxLength),
      onInput: onInput,
      lifetime: lifetime,
    );
  }

  static Future<InternetAddress?> _lanAddress() async {
    if (Platform.isAndroid) {
      try {
        final networks = await const MethodChannel(
          'kazumi/tv',
        ).invokeListMethod<dynamic>('getLanAddresses');
        final selected = TvLanAddress.select([
          for (final value in networks ?? [])
            if (value is Map &&
                value['address'] is String &&
                value['interface'] is String)
              TvLanAddress(
                value['address'] as String,
                value['interface'] as String,
                active: value['active'] == true,
              ),
        ]);
        if (selected != null) return selected;
      } on PlatformException {
        // Older firmware may not expose link properties; use physical NICs.
      } on MissingPluginException {
        // Desktop tests and older platform shells use the portable fallback.
      }
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return TvLanAddress.select([
      for (final interface in interfaces)
        for (final address in interface.addresses)
          TvLanAddress(address.address, interface.name),
    ]);
  }

  Future<void> _respond(
    HttpRequest request,
    int status,
    String body, {
    bool html = false,
  }) async {
    final response = request.response;
    response.statusCode = status;
    response.headers
      ..contentType = html ? ContentType.html : ContentType.json
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'",
      );
    response.write(body);
    await response.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (_closed || request.uri.path != '/$_token') {
        await _respond(request, HttpStatus.notFound, '{"ok":false}');
        return;
      }
      if (request.method == 'GET') {
        await _respond(request, HttpStatus.ok, _page(), html: true);
        return;
      }
      if (request.method != 'POST') {
        await _respond(request, HttpStatus.methodNotAllowed, '{"ok":false}');
        return;
      }
      final origin = request.headers.value('origin');
      if ((origin != null && origin != url.origin) ||
          request.headers.contentType?.mimeType != 'application/json') {
        await _respond(request, HttpStatus.forbidden, '{"ok":false}');
        return;
      }
      final maxBodyBytes = TvInputLimits.bodyBytes(maxLength);
      if (request.contentLength > maxBodyBytes) {
        await _respond(
          request,
          HttpStatus.requestEntityTooLarge,
          jsonEncode({
            'ok': false,
            'error': 'request_too_large',
            'maxLength': maxLength,
          }),
        );
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        if (bytes.length + chunk.length > maxBodyBytes) {
          await _respond(
            request,
            HttpStatus.requestEntityTooLarge,
            jsonEncode({
              'ok': false,
              'error': 'request_too_large',
              'maxLength': maxLength,
            }),
          );
          return;
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> ||
          data['text'] is! String ||
          data['submit'] is! bool) {
        await _respond(request, HttpStatus.badRequest, '{"ok":false}');
        return;
      }
      final text = data['text'] as String;
      final submit = data['submit'] as bool;
      if (text.length > maxLength) {
        await _respond(
          request,
          HttpStatus.requestEntityTooLarge,
          jsonEncode({
            'ok': false,
            'error': 'input_too_long',
            'maxLength': maxLength,
          }),
        );
        return;
      }
      if (_closed || !_onInput(text, submit)) {
        await _respond(request, HttpStatus.conflict, '{"ok":false}');
        return;
      }
      await _respond(request, HttpStatus.ok, '{"ok":true}');
      // Close the TV dialog only after the phone receives its acknowledgement.
      if (submit && !_closed) _submitted.add(null);
    } catch (_) {
      // Do not log URLs, tokens or input content. A disconnected phone must not
      // crash the app, and a response already closed cannot be written again.
      try {
        await _respond(request, HttpStatus.badRequest, '{"ok":false}');
      } catch (_) {}
    }
  }

  String _page() {
    const escape = HtmlEscape();
    final input = obscureText
        ? '<input id="text" type="password" autocomplete="off">'
        : '<textarea id="text" rows="5">${escape.convert(initialText)}</textarea>';
    return '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kazumi · 手机输入</title><style>
body{margin:0;background:#101c2c;color:#f5f1e8;font:18px system-ui,sans-serif}
main{max-width:600px;margin:48px auto;padding:24px}h1{font-size:28px}
p{color:#aab9cb;line-height:1.6}textarea,input{box-sizing:border-box;width:100%;font:inherit;padding:16px;background:#1c2c41;color:#f5f1e8;border:2px solid #aab9cb;border-radius:12px}
button{font:inherit;margin:16px 12px 0 0;padding:14px 20px;border:0;border-radius:10px;background:#ebc889;color:#101c2c}button:disabled{opacity:.5}
</style></head><body><main><h1>${escape.convert(title)}</h1>
<p>输入完成后发送到电视。关闭电视上的扫码窗口后，此页面即失效。</p>
$input<div><button id="fill">仅填入</button><button id="send">发送到电视</button></div>
<p id="status" role="status"></p></main><script>
const field=document.getElementById('text'), status=document.getElementById('status');
const buttons=[document.getElementById('fill'),document.getElementById('send')];
async function send(submit){if(field.value.length>$maxLength){status.textContent='内容过长，最多支持 $maxLength 字符。原内容已保留，请缩短后重试。';return;}buttons.forEach(b=>b.disabled=true);status.textContent='正在发送…';
try{const response=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:field.value,submit})});
if(response.status===413){status.textContent='内容超出长度限制，最多支持 $maxLength 字符。原内容已保留。';buttons.forEach(b=>b.disabled=false);return;}if(!response.ok)throw Error();status.textContent=submit?'已发送，请看电视。':'已填入电视。';if(submit){field.value='';return;}}
catch(e){status.textContent='连接已结束或电视暂不可输入，请在电视上重新打开扫码输入。';}
buttons.forEach(b=>b.disabled=false);}
buttons[0].onclick=()=>send(false);buttons[1].onclick=()=>send(true);
</script></body></html>''';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    await _subscription.cancel();
    await _server.close(force: true);
    await _submitted.close();
  }
}
