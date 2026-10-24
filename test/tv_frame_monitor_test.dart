import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_frame_monitor.dart';

FrameTiming frame(int vsync, {int build = 1000, int raster = 2000}) =>
    FrameTiming(
      vsyncStart: vsync,
      buildStart: vsync,
      buildFinish: vsync + build,
      rasterStart: vsync + build,
      rasterFinish: vsync + build + raster,
      rasterFinishWallTime: vsync + build + raster,
    );

void main() {
  test('reports frame cadence and render time independently', () {
    final monitor = TvFrameMonitor();
    monitor.record([frame(0), frame(16667), frame(33334, raster: 30000)]);
    expect(monitor.summary(60), contains('60.0 fps / 60.0 Hz'));
    expect(monitor.summary(60), contains('绘制 p95: 30.0 ms'));
    expect(monitor.summary(60), contains('超预算: 33%'));
  });

  test(
    'bounded history discards old stalls instead of reporting them forever',
    () {
      final monitor = TvFrameMonitor(capacity: 2);
      monitor.record([frame(0, raster: 50000), frame(16667), frame(33334)]);
      expect(monitor.summary(60), contains('超预算: 0%'));
    },
  );

  test(
    'duplicate timestamps and a restarted clock cannot produce invalid fps',
    () {
      final monitor = TvFrameMonitor();
      monitor.record([frame(10000), frame(10000)]);
      expect(monitor.summary(60), contains('等待采样'));
      monitor.record([frame(0), frame(16667)]);
      expect(monitor.summary(double.nan), contains('60.0 fps / 60.0 Hz'));
    },
  );
  test('menu rendering cannot overwrite the preceding playback window', () {
    final monitor = TvFrameMonitor(capacity: 2);
    monitor.record([frame(0), frame(16667)]);
    monitor.capturePlaybackWindow(60);
    final playback = monitor.playbackWindow;
    monitor.record([frame(50000, raster: 80000), frame(100000, raster: 80000)]);
    expect(monitor.summary(60), contains('20.0 fps'));
    expect(monitor.playbackWindow, playback);
    expect(playback, contains('60.0 fps'));
  });
}
