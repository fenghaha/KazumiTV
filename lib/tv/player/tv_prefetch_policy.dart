import 'package:kazumi/tv/player/tv_device_profile.dart';

/// Bound eager TLS/disk-cache work only in the validated XGIMI build profile.
/// Byte-cache sizing and the user's low-memory setting remain upstream-owned.
abstract final class TvPrefetchPolicy {
  static const int constrainedMemoryBytes = 2 * 1024 * 1024 * 1024;
  static const int constrainedSeconds = 60;

  static int? limit({
    required bool androidTv,
    required String deviceProfile,
    required int? totalMemoryBytes,
  }) {
    if (!TvDeviceProfile.usesXgimiTuning(
          androidTv: androidTv,
          deviceProfile: deviceProfile,
        ) ||
        totalMemoryBytes == null ||
        totalMemoryBytes <= 0 ||
        totalMemoryBytes > constrainedMemoryBytes) {
      return null;
    }
    return constrainedSeconds;
  }
}
