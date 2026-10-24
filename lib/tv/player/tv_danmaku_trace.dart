import 'dart:developer' as developer;
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/tv/player/tv_device_profile.dart';
import 'package:kazumi/tv/tv_mode.dart';

/// Opt-in, profile-only timing for synchronous admission/layout/bitmap work.
/// Records only item type and length, never comment text or media identifiers.
abstract final class TvDanmakuTrace {
  static bool shouldTrace({
    required bool profileBuild,
    required bool requested,
    required bool androidTv,
    required String deviceProfile,
  }) =>
      profileBuild &&
      requested &&
      TvDeviceProfile.usesXgimiTuning(
        androidTv: androidTv,
        deviceProfile: deviceProfile,
      );

  static bool get enabled => shouldTrace(
    profileBuild: kProfileMode,
    requested: const bool.fromEnvironment('KAZUMI_TV_TRACE_DANMAKU'),
    androidTv: TvMode.enabled && Platform.isAndroid,
    deviceProfile: TvDeviceProfile.current,
  );

  static void add(
    DanmakuController<dynamic> controller,
    DanmakuContentItem<dynamic> item,
  ) {
    if (!enabled) {
      controller.addDanmaku(item);
      return;
    }
    developer.Timeline.timeSync(
      'TV.Danmaku.add',
      () => controller.addDanmaku(item),
      arguments: {'type': item.type.name, 'codeUnits': item.text.length},
    );
  }
}
