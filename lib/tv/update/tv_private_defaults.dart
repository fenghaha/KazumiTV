import 'package:kazumi/services/storage/storage.dart';

/// The one-time private bootstrap keeps an existing implicit server choice on
/// the device before moving to distributable builds without private defines.
/// An explicitly empty choice remains empty; no address is bundled publicly.
Future<void> retainPrivateTvDefaults() async {
  const bundled = String.fromEnvironment('KAZUMI_DANMAKU_BASE_URL');
  if (bundled.isEmpty) return;
  final current = GStorage.getSetting(SettingsKeys.danmakuApiBaseUrl);
  if (current.trim().isNotEmpty) {
    await GStorage.putSetting(SettingsKeys.danmakuApiBaseUrl, current);
  }
}
