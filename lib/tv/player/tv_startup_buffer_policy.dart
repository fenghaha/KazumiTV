import 'package:kazumi/tv/player/tv_device_profile.dart';

/// Let mpv hold network playback until a useful media buffer is available.
/// This is separate from prefetch limits, user pause and cache byte sizing.
abstract final class TvStartupBufferPolicy {
  static const seconds = 10;

  static Map<String, String> options({
    required bool androidTv,
    required String deviceProfile,
    required bool localPlayback,
  }) {
    if (!androidTv ||
        deviceProfile != TvDeviceProfile.hisenseMt9655 ||
        localPlayback) {
      return const {};
    }
    return const {
      'cache-pause': 'yes',
      'cache-pause-wait': '$seconds',
      'cache-pause-initial': 'yes',
    };
  }

  static Future<bool> apply({
    required Map<String, String> values,
    required Future<void> Function(String, String) setProperty,
    required bool Function() isCurrent,
  }) async {
    for (final entry in values.entries) {
      if (!isCurrent()) return false;
      await setProperty(entry.key, entry.value);
    }
    return isCurrent();
  }
}
