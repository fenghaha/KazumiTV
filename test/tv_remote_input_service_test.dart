import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/input/remote_input_service.dart';

void main() {
  late RemoteInputService service;
  late HttpClient client;
  late Uri url;
  setUp(() async {
    service = RemoteInputService(
      port: 0,
      addressProvider: () async => InternetAddress.loopbackIPv4,
    );
    client = HttpClient();
    url = await service.ensureStarted();
  });
  tearDown(() async {
    client.close(force: true);
    await service.close();
  });
  Future<(int, String)> get(String path) async {
    final request = await client.getUrl(url.resolve(path));
    final response = await request.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  Future<int> post(
    String id,
    String text, {
    bool submit = false,
    String? origin,
  }) async {
    final request = await client.postUrl(url.resolve('/api/input'));
    request.headers.contentType = ContentType.json;
    if (origin != null) request.headers.set('origin', origin);
    request.write(jsonEncode({'id': id, 'text': text, 'submit': submit}));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  test('fixed entry and port survive fields closing and reopening', () async {
    expect((await get('/')).$1, 200);
    expect((await get('/api/field')).$2, '{"active":false}');
    final lease = service.attach(
      title: '搜索',
      text: () => '原文字',
      canApply: () => true,
      onInput: (_, submit) => true,
    );
    expect(jsonDecode((await get('/api/field')).$2)['title'], '搜索');
    lease.close();
    expect((await service.ensureStarted()).toString(), url.toString());
    expect((await get('/')).$1, 200);
    expect((await get('/api/field')).$2, '{"active":false}');
  });
  test('browser submits to current field and stale tabs cannot write into a replacement', () async {
    var value = '';
    var submits = 0;
    final old = service.attach(
      title: 'A',
      text: () => value,
      canApply: () => true,
      onInput: (text, submit) {
        value = text;
        return true;
      },
      onSubmit: () => submits++,
    );
    expect(await post(old.id, '电脑输入', submit: true), 200);
    expect(value, '电脑输入');
    expect(submits, 1);
    final next = service.attach(
      title: 'B',
      text: () => value,
      canApply: () => true,
      onInput: (text, submit) {
        value = text;
        return true;
      },
    );
    old.close();
    expect(await post(old.id, '错误覆盖'), 409);
    expect(value, '电脑输入');
    expect(await post(next.id, '新输入'), 200);
    expect(value, '新输入');
  });
  test('secrets are never prefilled; disabled fields, cross-origin and excessive input are rejected', () async {
    var enabled = true;
    var applied = 0;
    final lease = service.attach(
      title: '密码',
      text: () => 'never-expose-fixture-secret',
      canApply: () => enabled,
      onInput: (_, submit) {
        applied++;
        return true;
      },
      obscureText: true,
      maxLength: 4,
    );
    expect((await get('/api/field')).$2, isNot(contains('never-expose')));
    expect((await get('/')).$2, isNot(contains('never-expose')));
    expect(await post(lease.id, 'text', origin: 'http://evil.test'), 403);
    expect(await post(lease.id, '12345'), 413);
    enabled = false;
    expect(await post(lease.id, 'text'), 409);
    expect(applied, 0);
  });
  test(
    'a delayed request for a previous field is rejected after focus changes',
    () async {
      var applied = 0;
      final lease = service.attach(
        title: 'first',
        text: () => '',
        canApply: () => true,
        onInput: (_, submit) {
          applied++;
          return true;
        },
      );
      final request = await client.postUrl(url.resolve('/api/input'));
      request.headers.contentType = ContentType.json;
      final payload = utf8.encode(
        jsonEncode({'id': lease.id, 'text': 'late', 'submit': false}),
      );
      request.contentLength = payload.length;
      request.add(payload.take(1).toList());
      await request.flush();
      service.attach(
        title: 'second',
        text: () => '',
        canApply: () => true,
        onInput: (_, submit) => true,
      );
      request.add(payload.skip(1).toList());
      final response = await request.close();
      expect(response.statusCode, 409);
      await response.drain<void>();
      expect(applied, 0);
    },
  );
}
