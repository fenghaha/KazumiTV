import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_prefetch_policy.dart';

void main() {
  test('2 GiB Android TV gets a time bound without shrinking the byte cache', () {
    expect(TvPrefetchPolicy.limit(androidTv: true, totalMemoryBytes: 1941639168), 60);
    expect(TvPrefetchPolicy.limit(androidTv: true, totalMemoryBytes: 2 * 1024 * 1024 * 1024), 60);
  });
  test('unknown hardware, larger TVs and non-TV builds keep upstream behavior', () {
    for (final memory in [null, 0, -1, 4 * 1024 * 1024 * 1024]) {
      expect(TvPrefetchPolicy.limit(androidTv: true, totalMemoryBytes: memory), isNull);
    }
    expect(TvPrefetchPolicy.limit(androidTv: false, totalMemoryBytes: 1941639168), isNull);
  });
}
