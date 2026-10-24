/// Bound eager TLS/disk-cache work on memory-constrained Android televisions.
/// Byte-cache sizing and the user's low-memory setting remain upstream-owned.
abstract final class TvPrefetchPolicy {
  static const int constrainedMemoryBytes = 2 * 1024 * 1024 * 1024;
  static const int constrainedSeconds = 60;

  static int? limit({required bool androidTv, required int? totalMemoryBytes}) {
    if (!androidTv ||
        totalMemoryBytes == null ||
        totalMemoryBytes <= 0 ||
        totalMemoryBytes > constrainedMemoryBytes) {
      return null;
    }
    return constrainedSeconds;
  }
}
