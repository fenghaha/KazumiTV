import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_danmaku_trace.dart';
import 'package:kazumi/tv/player/tv_device_profile.dart';

class _Canvas extends Fake implements DanmakuController<dynamic> {
  _Canvas(this.receive);
  final void Function(DanmakuContentItem<dynamic>) receive;
  @override
  void Function(DanmakuContentItem<dynamic>) get addDanmaku => receive;
}

void main() {
  test('timing requires profile mode, explicit request and XGIMI target', () {
    for (final profile in [true, false]) {
      for (final requested in [true, false]) {
        for (final target in [
          TvDeviceProfile.generic,
          TvDeviceProfile.xgimiZ9x,
          'hisense',
        ]) {
          final actual = TvDanmakuTrace.shouldTrace(
            profileBuild: profile,
            requested: requested,
            androidTv: true,
            deviceProfile: target,
          );
          expect(
            actual,
            profile && requested && target == TvDeviceProfile.xgimiZ9x,
          );
        }
      }
    }
    expect(
      TvDanmakuTrace.shouldTrace(
        profileBuild: true,
        requested: true,
        androidTv: false,
        deviceProfile: TvDeviceProfile.xgimiZ9x,
      ),
      isFalse,
    );
  });

  test(
    'disabled trace forwards the original comment once without rewriting',
    () {
      final received = <DanmakuContentItem<dynamic>>[];
      final item = DanmakuContentItem<dynamic>('原始弹幕');
      TvDanmakuTrace.add(_Canvas(received.add), item);
      expect(received, hasLength(1));
      expect(identical(received.single, item), isTrue);
    },
  );

  test('disabled trace preserves the original failure instead of retrying', () {
    final failure = StateError('canvas disposed');
    var calls = 0;
    final canvas = _Canvas((_) {
      calls++;
      throw failure;
    });
    expect(
      () => TvDanmakuTrace.add(canvas, DanmakuContentItem('x')),
      throwsA(same(failure)),
    );
    expect(calls, 1);
  });
}
