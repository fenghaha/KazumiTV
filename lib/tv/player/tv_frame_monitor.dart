import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Bounded, in-memory timings. Active only while a TV playback overlay exists.
class TvFrameMonitor {
  TvFrameMonitor({this.capacity = 180}) : assert(capacity > 1);

  static final shared = TvFrameMonitor(capacity: 1800);
  static bool _profileExtensionRegistered = false;
  final int capacity;
  final ListQueue<FrameTiming> _frames = ListQueue();
  int _owners = 0;
  String? _playbackWindow;
  String? get playbackWindow => _playbackWindow;

  void capturePlaybackWindow(double refreshRate) {
    _playbackWindow = summary(refreshRate);
  }

  void start() {
    if (_owners++ == 0) {
      _frames.clear();
      _playbackWindow = null;
      SchedulerBinding.instance.addTimingsCallback(record);
      _registerProfileExtension();
    }
  }

  void _registerProfileExtension() {
    if (!kProfileMode || _profileExtensionRegistered) return;
    _profileExtensionRegistered = true;
    // Read-only counters over the authenticated Dart VM service. No playback
    // commands, URLs or user settings are exposed. Absent from release builds.
    developer.registerExtension('ext.kazumi.tv.frames', (_, parameters) async {
      if (parameters['reset'] == 'true') _frames.clear();
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'capacity': capacity,
        'frames': [
          for (final frame in _frames)
            {
              'vsyncUs': frame.timestampInMicroseconds(FramePhase.vsyncStart),
              'buildStartUs': frame.timestampInMicroseconds(FramePhase.buildStart),
              'buildFinishUs': frame.timestampInMicroseconds(FramePhase.buildFinish),
              'rasterStartUs': frame.timestampInMicroseconds(FramePhase.rasterStart),
              'rasterFinishUs': frame.timestampInMicroseconds(FramePhase.rasterFinish),
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
            },
        ],
      }));
    });
    // Some TV firmware disables logcat, including the VM service startup line.
    // Keep authentication enabled; adb run-as can read this app-private file.
    developer.Service.getInfo().then<void>((info) async {
      final uri = info.serverUri;
      if (uri == null) return;
      await File('${Directory.systemTemp.path}/kazumi-tv-profile-service.json')
          .writeAsString(jsonEncode({'uri': uri.toString()}));
    }).catchError((Object _) {
      // Diagnostics must never affect playback or request broader file access.
    });
  }

  void stop() {
    if (_owners == 0) return;
    if (--_owners == 0) {
      SchedulerBinding.instance.removeTimingsCallback(record);
      _frames.clear();
      _playbackWindow = null;
    }
  }

  void record(List<FrameTiming> frames) {
    for (final frame in frames) {
      final time = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_frames.isNotEmpty) {
        final previous = _frames.last.timestampInMicroseconds(
          FramePhase.vsyncStart,
        );
        if (time == previous) continue;
        if (time < previous) _frames.clear();
      }
      _frames.add(frame);
      if (_frames.length > capacity) _frames.removeFirst();
    }
  }

  String summary(double refreshRate) {
    if (_frames.length < 2) return 'Flutter 帧耗时: 等待采样';
    final span =
        _frames.last.timestampInMicroseconds(FramePhase.vsyncStart) -
        _frames.first.timestampInMicroseconds(FramePhase.vsyncStart);
    final fps = (_frames.length - 1) * 1000000 / span;
    final build = _frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = _frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    final percentile = (_frames.length * 0.95).ceil() - 1;
    final refresh = refreshRate.isFinite && refreshRate > 0
        ? refreshRate
        : 60.0;
    final budget = 1000000 / refresh;
    final slow = _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > budget ||
              f.rasterDuration.inMicroseconds > budget,
        )
        .length;
    return 'Flutter: ${fps.toStringAsFixed(1)} fps / ${refresh.toStringAsFixed(1)} Hz\n'
        'UI p95: ${(build[percentile] / 1000).toStringAsFixed(1)} ms  '
        '绘制 p95: ${(raster[percentile] / 1000).toStringAsFixed(1)} ms  '
        '超预算: ${(slow * 100 / _frames.length).toStringAsFixed(0)}%';
  }
}
