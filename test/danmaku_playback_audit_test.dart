import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _UnusedDownloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Canvas implements canvas.DanmakuController {
  int clears = 0;
  @override
  VoidCallback get clear => () { clears++; };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Real API parsing/transport path, with independently controlled responses.
class _Comments implements HttpClientAdapter {
  final pending = <int, Completer<ResponseBody>>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final id = int.parse(options.uri.pathSegments.last);
    return (pending[id] = Completer<ResponseBody>()).future;
  }

  Future<void> started(int id) async {
    for (var i = 0; i < 100 && !pending.containsKey(id); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(pending, contains(id));
  }

  void complete(int id, String message, {int status = 200}) {
    pending[id]!.complete(
      ResponseBody.fromString(
        jsonEncode({
          'comments': [
            {'p': '10.41,1,16777215,[dandan]', 'm': message},
          ],
        }),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

DanmakuEntry _entry(double second, [String message = '最后是彩蛋么。。']) =>
    DanmakuEntry(
      message: message,
      time: second,
      type: 1,
      color: Colors.white,
      source: '[dandan]',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PlayerDanmakuController controller;
  late _Canvas overlay;
  late _Comments transport;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('danmaku_audit');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.danmakuDeduplication, false);
    await GStorage.putSetting(SettingsKeys.danmakuTimeOffset, 0.0);
    await GStorage.putSetting(
      SettingsKeys.danmakuApiBaseUrl,
      'https://fixture.invalid',
    );
    controller = PlayerDanmakuController(
      isLocalPlayback: () => false,
      downloadController: _UnusedDownloads(),
    );
    overlay = _Canvas();
    controller.canvasController = overlay;
    transport = _Comments();
    DioFactory.danmakuCustomDio.httpClientAdapter = transport;
  });
  tearDown(() {
    controller.dispose();
    DioFactory.reset();
  });

  test(
    'one API record produces one dispatch despite repeated and jittering positions',
    () {
      controller.addDanmakus([_entry(1418.41), _entry(1419.1, '下一秒')]);
      final shown = <String>[];
      for (final ms in [1418410, 1418410, 1418990, 1419200, 1418800, 1419300]) {
        shown.addAll(
          controller
              .takeDanmakusForPlaybackPosition(Duration(milliseconds: ms))
              .map((e) => e.message),
        );
      }
      expect(shown, ['最后是彩蛋么。。', '下一秒']);
    },
  );

  test(
    'explicit rewind permits replay, but invalidates the old delayed batch',
    () {
      controller.addDanmakus([_entry(10.4)]);
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
        hasLength(1),
      );
      final oldGeneration = controller.scheduledDanmakuGeneration;
      controller.clearAndInvalidateScheduledDanmakus();
      expect(controller.scheduledDanmakuGeneration, greaterThan(oldGeneration));
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
        hasLength(1),
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
        isEmpty,
      );
    },
  );

  test(
    'pause/buffer invalidation preserves the canvas and does not replay the bucket',
    () {
      controller.addDanmakus([_entry(10.1), _entry(11.1, '继续')]);
      controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10));
      final oldGeneration = controller.scheduledDanmakuGeneration;
      final oldClears = overlay.clears;
      controller.invalidateScheduledDanmakus();
      expect(controller.scheduledDanmakuGeneration, greaterThan(oldGeneration));
      expect(overlay.clears, oldClears);
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
        isEmpty,
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 11)),
        hasLength(1),
      );
    },
  );

  test(
    'timer gaps catch up a short interval once; large jumps do not flood history',
    () {
      controller.addDanmakus([
        for (var i = 10; i <= 30; i++) _entry(i.toDouble(), '$i'),
      ]);
      expect(
        controller
            .takeDanmakusForPlaybackPosition(const Duration(seconds: 10))
            .map((e) => e.message),
        ['10'],
      );
      expect(
        controller
            .takeDanmakusForPlaybackPosition(const Duration(seconds: 13))
            .map((e) => e.message),
        ['11', '12', '13'],
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 13)),
        isEmpty,
      );
      expect(
        controller
            .takeDanmakusForPlaybackPosition(const Duration(seconds: 30))
            .map((e) => e.message),
        ['30'],
      );
    },
  );

  test(
    'negative offset positions do not consume the first source bucket',
    () async {
      controller.addDanmakus([_entry(0)]);
      await GStorage.putSetting(SettingsKeys.danmakuTimeOffset, 5.0);
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 4)),
        isEmpty,
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 5)),
        hasLength(1),
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 5)),
        isEmpty,
      );
      await GStorage.putSetting(SettingsKeys.danmakuTimeOffset, 0.0);
      controller.clearAndInvalidateScheduledDanmakus();
      expect(
        controller.takeDanmakusForPlaybackPosition(Duration.zero),
        hasLength(1),
      );
    },
  );

  test(
    'applying a replacement load twice does not append duplicate entries',
    () {
      final result = DanmakuLoadResult.success(
        danmakus: [_entry(10.4)],
        bangumiID: 123,
      );
      controller.applyDanmakuLoad(result, enableDanmaku: true);
      controller.applyDanmakuLoad(result, enableDanmaku: true);
      expect(controller.danDanmakus[10], hasLength(1));
      expect(
        controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
        hasLength(1),
      );
    },
  );

  test('distinct same-text comments at later timestamps remain separate', () {
    controller.addDanmakus([_entry(10.1), _entry(20.1)]);
    expect(
      controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 10)),
      hasLength(1),
    );
    expect(
      controller.takeDanmakusForPlaybackPosition(const Duration(seconds: 20)),
      hasLength(1),
    );
  });

  test(
    'rapid off/on invalidates scheduled callbacks from the previous enabled state',
    () {
      controller.applyDanmakuLoad(
        DanmakuLoadResult.success(danmakus: [_entry(10.1)], bangumiID: 1),
        enableDanmaku: true,
      );
      final oldGeneration = controller.scheduledDanmakuGeneration;
      controller.setDanmakuEnabled(false);
      controller.setDanmakuEnabled(true);
      expect(controller.scheduledDanmakuGeneration, greaterThan(oldGeneration));
      expect(controller.danDanmakus[10], hasLength(1));
    },
  );

  test(
    'initial load and stop are safe before the drawing controller is attached',
    () {
      final unattached = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: _UnusedDownloads(),
      );
      expect(unattached.beginDanmakuLoad, returnsNormally);
      expect(unattached.cancelPendingDanmakuLoad, returnsNormally);
      expect(unattached.dispose, returnsNormally);
    },
  );

  test(
    'an older manual response cannot append to the newer selection',
    () async {
      final old = controller.loadManualDanmaku(1);
      await transport.started(1);
      final newest = controller.loadManualDanmaku(2);
      await transport.started(2);
      transport.complete(2, '新来源');
      expect(await newest, isTrue);
      transport.complete(1, '旧来源');
      expect(await old, isNull);
      expect(controller.danDanmakus[10]!.map((e) => e.message), ['新来源']);
      expect(controller.danmakuLoading, isFalse);
    },
  );

  test('a stale request cannot finish the newer loading indicator', () async {
    final old = controller.loadManualDanmaku(1);
    await transport.started(1);
    final newest = controller.loadManualDanmaku(2);
    await transport.started(2);
    transport.complete(1, '旧来源');
    expect(await old, isNull);
    expect(controller.danmakuLoading, isTrue);
    transport.complete(2, '新来源');
    await newest;
    expect(controller.danmakuLoading, isFalse);
  });

  test(
    'automatic episode loading invalidates an in-flight manual selection',
    () async {
      final old = controller.loadManualDanmaku(1);
      await transport.started(1);
      controller.beginDanmakuLoad();
      controller.applyDanmakuLoad(
        DanmakuLoadResult.success(
          danmakus: [_entry(10.1, '新一集')],
          bangumiID: 8,
        ),
        enableDanmaku: true,
      );
      transport.complete(1, '上一集');
      expect(await old, isNull);
      expect(controller.danDanmakus[10]!.single.message, '新一集');
      expect(controller.bangumiID, 8);
    },
  );

  test(
    'stop and route disposal reject late responses before any new episode begins',
    () async {
      for (final dispose in [false, true]) {
        final id = dispose ? 2 : 1;
        final old = controller.loadManualDanmaku(id);
        await transport.started(id);
        if (dispose) {
          controller.dispose();
        } else {
          controller.cancelPendingDanmakuLoad();
        }
        transport.complete(id, '旧播放页');
        expect(await old, isNull);
        expect(controller.danDanmakus, isEmpty);
        expect(controller.danmakuOn, isFalse);
      }
    },
  );

  test(
    'closing a source sheet prevents its successful response from mutating playback',
    () async {
      var mounted = true;
      final old = controller.loadManualDanmaku(1, canApply: () => mounted);
      await transport.started(1);
      mounted = false;
      transport.complete(1, '已关闭的选择');
      expect(await old, isNull);
      expect(controller.danDanmakus, isEmpty);
      expect(controller.danmakuLoading, isFalse);
    },
  );

  test(
    'a stale HTTP failure stays silent and cannot disturb a new source',
    () async {
      final old = controller.loadManualDanmaku(1);
      await transport.started(1);
      final newest = controller.loadManualDanmaku(2);
      await transport.started(2);
      transport.complete(2, '新来源');
      await newest;
      transport.complete(1, '服务器错误', status: 500);
      expect(await old, isNull);
      expect(controller.danDanmakus[10]!.single.message, '新来源');
    },
  );
}
