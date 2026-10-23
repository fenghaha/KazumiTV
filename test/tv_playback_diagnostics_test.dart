import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_playback_diagnostics.dart';

void main() {
  test('native byte rate is converted to both byte and bit units', () {
    final text = formatTvPlaybackDiagnostics({
      'demuxer-cache-state':
          '{"raw-input-rate":1500000,"file-cache-bytes":10485760}',
      'demuxer-cache-duration': '0.256000',
      'paused-for-cache': 'yes',
      'hwdec-current': 'mediacodec',
      'current-vo': 'mediacodec_embed',
    });
    expect(text, contains('1.50 MB/s (12.00 Mbps)'));
    expect(text, contains('0.26 秒'));
    expect(text, contains('缓冲暂停: yes'));
    expect(text, contains('缓存文件: 10.00 MiB'));
  });

  test('unknown, unsupported, or malformed properties stay unknown', () {
    for (final cache in ['', 'not-json', '[]', '{"raw-input-rate":"NaN"}']) {
      final text = formatTvPlaybackDiagnostics({'demuxer-cache-state': cache});
      expect(text, contains('读取: — MB/s (— Mbps)'));
      expect(text, contains('硬解: —'));
      expect(text, isNot(contains('NaN')));
    }
  });

  test('unrecognized cache data is never copied into the diagnostic UI', () {
    final text = formatTvPlaybackDiagnostics({
      'demuxer-cache-state': '{"unexpected":"private-value","total-bytes":99}',
    });
    expect(text, isNot(contains('private-value')));
    expect(text, contains('缓存文件: — MiB'));
  });
}
