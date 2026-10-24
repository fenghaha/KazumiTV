import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_device_profile.dart';
import 'package:kazumi/tv/player/tv_prefetch_policy.dart';

void main() {
  int? limit(String profile, int? memory, {bool tv = true}) =>
      TvPrefetchPolicy.limit(
        androidTv: tv,
        deviceProfile: profile,
        totalMemoryBytes: memory,
      );

  test(
    'only the explicit validated Z9X build receives the 60-second window',
    () {
      expect(limit(TvDeviceProfile.xgimiZ9x, 1941639168), 60);
      expect(limit(TvDeviceProfile.xgimiZ9x, 2 * 1024 * 1024 * 1024), 60);
    },
  );

  test('generic and unvalidated device profiles do not inherit Z9X tuning', () {
    for (final profile in [TvDeviceProfile.generic, 'hisense', '', 'xgimi']) {
      expect(limit(profile, 1941639168), isNull, reason: profile);
    }
  });

  test('unknown hardware, changed RAM cohort and non-TV remain upstream', () {
    for (final memory in [null, 0, -1, 4 * 1024 * 1024 * 1024]) {
      expect(limit(TvDeviceProfile.xgimiZ9x, memory), isNull);
    }
    expect(limit(TvDeviceProfile.xgimiZ9x, 1941639168, tv: false), isNull);
  });
}
