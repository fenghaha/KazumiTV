import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_device_profile.dart';
import 'package:kazumi/tv/player/tv_startup_buffer_policy.dart';

void main() {
  Map<String, String> options({
    String profile = TvDeviceProfile.hisenseMt9655,
    bool tv = true,
    bool local = false,
  }) => TvStartupBufferPolicy.options(
    androidTv: tv,
    deviceProfile: profile,
    localPlayback: local,
  );

  test('explicit Hisense network target waits for ten seconds of media', () {
    expect(options(), {
      'cache-pause': 'yes',
      'cache-pause-wait': '10',
      'cache-pause-initial': 'yes',
    });
    for (final untouched in [
      'pause', 'cache-secs', 'demuxer-max-bytes', 'vo', 'hwdec',
    ]) {
      expect(options().containsKey(untouched), isFalse);
    }
  });

  test('generic, XGIMI, other platforms and local playback stay unchanged', () {
    for (final profile in [TvDeviceProfile.generic, TvDeviceProfile.xgimiZ9x,
      'hisense', '']) {
      expect(options(profile: profile), isEmpty);
    }
    expect(options(tv: false), isEmpty);
    expect(options(local: true), isEmpty);
  });

  test('configure writes native options before handing control back to open', () async {
    final writes = <String>[];
    final configured = await TvStartupBufferPolicy.apply(
      values: options(),
      setProperty: (key, value) async => writes.add('$key=$value'),
      isCurrent: () => true,
    );
    expect(configured, isTrue);
    expect(writes.last, 'cache-pause-initial=yes');
    expect(writes, hasLength(3));
  });

  test('a replaced player receives no later initialization writes', () async {
    var current = true;
    final started = Completer<void>();
    final release = Completer<void>();
    final writes = <String>[];
    final configured = TvStartupBufferPolicy.apply(
      values: options(),
      setProperty: (key, value) async {
        writes.add(key);
        started.complete();
        await release.future;
      },
      isCurrent: () => current,
    );
    await started.future;
    current = false;
    release.complete();
    expect(await configured, isFalse);
    expect(writes, ['cache-pause']);
  });

  test('an already cancelled player is not touched', () async {
    expect(await TvStartupBufferPolicy.apply(
      values: options(),
      setProperty: (_, _) async => fail('stale player write'),
      isCurrent: () => false,
    ), isFalse);
  });
}
