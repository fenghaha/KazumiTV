import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:kazumi/tv/input/tv_input_limits.dart';
import 'package:kazumi/tv/input/remote_input_session.dart';

/// Stable LAN entry point. Each active field has a fresh capability; stale
/// browser tabs cannot write into a different field. Never log URLs or values.
class RemoteInputService {
  RemoteInputService({
    this.port = 8765,
    Future<InternetAddress?> Function()? addressProvider,
  }) : _addressProvider = addressProvider ?? RemoteInputSession.lanAddress;
  static final instance = RemoteInputService();
  final int port;
  final Future<InternetAddress?> Function() _addressProvider;
  HttpServer? _server;
  Future<Uri>? _starting;
  RemoteInputLease? _active;
  Uri? get url => _server == null
      ? null
      : Uri(
          scheme: 'http',
          host: _server!.address.address,
          port: _server!.port,
        );

  Future<Uri> ensureStarted() =>
      _starting ??= _start().whenComplete(() => _starting = null);
  Future<Uri> _start() async {
    final address = await _addressProvider();
    if (address == null) throw const SocketException('No LAN connection');
    if (_server?.address.address == address.address) return url!;
    await _server?.close(force: true);
    _server = null;
    _server = await HttpServer.bind(address, port);
    _server!.listen(_handle);
    return url!;
  }

  RemoteInputLease attach({
    required String title,
    required String Function() text,
    required bool Function() canApply,
    required bool Function(String, bool) onInput,
    VoidCallback? onSubmit,
    bool obscureText = false,
    int maxLength = 4096,
  }) {
    final random = Random.secure();
    final lease = RemoteInputLease._(
      this,
      base64Url.encode(List.generate(24, (_) => random.nextInt(256))),
      title,
      text,
      canApply,
      onInput,
      onSubmit,
      obscureText,
      TvInputLimits.normalize(maxLength),
    );
    _active = lease;
    return lease;
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    String body, {
    bool html = false,
  }) async {
    request.response.statusCode = status;
    request.response.headers
      ..contentType = html ? ContentType.html : ContentType.json
      ..set('Cache-Control', 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
      );
    request.response.write(body);
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final host = request.headers.value('host');
      final authority = Uri.tryParse('http://${host ?? ''}');
      if (authority == null ||
          authority.port != _server?.port ||
          (authority.host != _server?.address.address &&
              !authority.host.endsWith('.lan'))) {
        await _reply(request, 403, '{"ok":false}');
        return;
      }
      final origin = request.headers.value('origin');
      if (origin != null && origin != authority.origin) {
        await _reply(request, 403, '{"ok":false}');
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/') {
        await _reply(request, 200, _page, html: true);
        return;
      }
      final lease = _active;
      final available = lease != null && lease.canApply();
      if (request.method == 'GET' && request.uri.path == '/api/field') {
        await _reply(
          request,
          200,
          jsonEncode(
            available
                ? {
                    'active': true,
                    'id': lease.id,
                    'title': lease.title,
                    'text': lease.obscureText ? '' : lease.text(),
                    'secret': lease.obscureText,
                    'maxLength': lease.maxLength,
                  }
                : {'active': false},
          ),
        );
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/api/input') {
        await _reply(request, 404, '{"ok":false}');
        return;
      }
      if (!available) {
        await _reply(request, 409, '{"ok":false}');
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        await _reply(request, 403, '{"ok":false}');
        return;
      }
      final limit = TvInputLimits.bodyBytes(lease.maxLength);
      if (request.contentLength > limit) {
        await _reply(request, 413, '{"ok":false}');
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        if (bytes.length + chunk.length > limit) {
          await _reply(request, 413, '{"ok":false}');
          return;
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map || data['text'] is! String || data['submit'] is! bool) {
        await _reply(request, 400, '{"ok":false}');
        return;
      }
      final text = data['text'] as String;
      if (text.length > lease.maxLength) {
        await _reply(request, 413, '{"ok":false}');
        return;
      }
      if (!identical(lease, _active) ||
          data['id'] != lease.id ||
          !lease.canApply() ||
          !lease.onInput(text, data['submit'] as bool)) {
        await _reply(request, 409, '{"ok":false}');
        return;
      }
      await _reply(request, 200, '{"ok":true}');
      if (data['submit'] == true && identical(lease, _active)) {
        lease.onSubmit?.call();
      }
    } catch (_) {
      try {
        await _reply(request, 400, '{"ok":false}');
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _active = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static const _page = r'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>KazumiTV 远程输入</title><style>
body{margin:0;background:#101c2c;color:#f5f1e8;font:18px system-ui,sans-serif}main{max-width:760px;margin:40px auto;padding:24px}h1{font-size:28px}p{color:#aab9cb;line-height:1.6}textarea,input{box-sizing:border-box;width:100%;font:inherit;padding:16px;background:#1c2c41;color:#f5f1e8;border:2px solid #aab9cb;border-radius:12px}button{font:inherit;margin:16px 12px 0 0;padding:14px 20px;border:0;border-radius:10px;background:#ebc889;color:#101c2c}button:disabled{opacity:.4}</style>
<main><h1>KazumiTV 远程输入</h1><p>收藏此地址，手机或电脑都能用。先用电视遥控器选中输入框，也可打开电视上的“扫码输入”。</p><h2 id="title">等待电视选择输入框</h2><textarea id="text" rows="6" disabled></textarea><input id="secret" type="password" autocomplete="off" hidden disabled><div><button id="fill" disabled>仅填入</button><button id="send" disabled>填入并确认</button></div><p id="status" role="status">正在连接电视…</p></main>
<script>
let current=null,dirty=false,busy=false;
const normal=document.getElementById('text'),secret=document.getElementById('secret'),title=document.getElementById('title'),status=document.getElementById('status'),buttons=[document.getElementById('fill'),document.getElementById('send')];
const field=()=>current&&current.secret?secret:normal;
normal.oninput=secret.oninput=()=>dirty=true;
async function poll(){if(busy)return;try{const response=await fetch('/api/field',{cache:'no-store'});if(!response.ok)throw Error();const next=await response.json();
if(!next.active){current=null;title.textContent='等待电视选择输入框';normal.disabled=secret.disabled=true;buttons.forEach(b=>b.disabled=true);status.textContent='网页保持打开即可，请在电视上选中要输入的位置。';return;}
if(!current||current.id!==next.id){current=next;dirty=false;normal.value=secret.value='';field().value=next.text||'';}else if(!dirty){field().value=next.text||'';}
current=next;title.textContent=next.title;normal.hidden=next.secret;secret.hidden=!next.secret;normal.disabled=secret.disabled=false;buttons.forEach(b=>b.disabled=false);status.textContent='已连接电视 · 最多 '+next.maxLength+' 字符';}
catch(e){status.textContent='电视暂不可连接，恢复网络后会自动重连。';buttons.forEach(b=>b.disabled=true);}}
async function send(submit){if(!current||busy)return;const value=field().value;if(value.length>current.maxLength){status.textContent='内容过长，请缩短后重试。';return;}busy=true;buttons.forEach(b=>b.disabled=true);
try{const response=await fetch('/api/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:current.id,text:value,submit})});if(response.status===409){status.textContent='电视已切换输入位置，请重新发送。';current=null;return;}if(!response.ok)throw Error();status.textContent='已发送到电视';dirty=false;if(current.secret||submit)field().value='';}
catch(e){status.textContent='发送未完成，内容已保留，请重试。';}finally{busy=false;buttons.forEach(b=>b.disabled=!current);}}
buttons[0].onclick=()=>send(false);buttons[1].onclick=()=>send(true);setInterval(poll,1000);poll();
</script></html>''';
}

typedef VoidCallback = void Function();

class RemoteInputLease {
  RemoteInputLease._(
    this._service,
    this.id,
    this.title,
    this.text,
    this.canApply,
    this.onInput,
    this.onSubmit,
    this.obscureText,
    this.maxLength,
  );
  final RemoteInputService _service;
  final String id, title;
  final String Function() text;
  final bool Function() canApply;
  final bool Function(String, bool) onInput;
  final VoidCallback? onSubmit;
  final bool obscureText;
  final int maxLength;
  void close() {
    if (identical(_service._active, this)) _service._active = null;
  }
}
