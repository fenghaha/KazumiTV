/// Explicit build target, not a guess based on RAM size or vendor name.
/// A generic/Hisense build must not inherit tuning accepted only on the Z9X.
abstract final class TvDeviceProfile {
  static const generic = 'generic';
  static const xgimiZ9x = 'xgimi-z9x';
  static const hisenseMt9655 = 'hisense-mt9655';
  static const current = String.fromEnvironment(
    'KAZUMI_TV_DEVICE_PROFILE',
    defaultValue: generic,
  );

  static bool usesXgimiTuning({
    required bool androidTv,
    required String deviceProfile,
  }) => androidTv && deviceProfile == xgimiZ9x;
}
