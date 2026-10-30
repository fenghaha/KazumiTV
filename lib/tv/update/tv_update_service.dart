import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/update/tv_update_manifest.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class TvUpdateService extends ChangeNotifier {
  TvUpdateService();
  static final instance = TvUpdateService();
  static const supportedBuild = bool.fromEnvironment('KAZUMI_TV');
  static const profile = String.fromEnvironment(
    'KAZUMI_TV_DEVICE_PROFILE',
    defaultValue: 'generic',
  );
  static const revision = String.fromEnvironment(
    'KAZUMI_TV_REVISION',
    defaultValue: 'dev',
  );

  TvInstalledBuild? installed;
  TvUpdateManifest? manifest;
  TvUpdateAsset? available;
  bool _startupChecked = false;
  Future<void>? _checking;

  Future<void> checkAtStartup() async {
    if (_startupChecked || !supportedBuild || !Platform.isAndroid) return;
    _startupChecked = true;
    try {
      await check();
    } catch (_) {
      /* Manual checks report failures. */
    }
  }

  Future<void> check() => _checking ??= _check().whenComplete(() {
    _checking = null;
  });

  Future<void> _check() async {
    final info = await TvMode.channel.invokeMapMethod<String, dynamic>(
      'getAppUpdateInfo',
    );
    if (info == null || info['package'] != tvUpdatePackage) {
      throw const FormatException('当前安装包不支持此电视更新渠道');
    }
    installed = TvInstalledBuild(
      packageName: info['package'] as String,
      versionCode: info['versionCode'] as int,
      versionName: info['versionName'] as String,
      abis: (info['abis'] as List).cast<String>(),
      sdk: info['sdk'] as int,
      profile: profile,
    );
    // Clear stale availability before any failed check can leave a download
    // button targeting a release which is no longer the current one.
    available = null;
    manifest = null;
    final raw = await DownloadHttpClient.instance.getPlain(
      tvUpdateManifestUrl,
      receiveTimeout: const Duration(seconds: 20),
    );
    if (raw.length > 256 * 1024) {
      throw const FormatException('电视更新清单过大');
    }
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('电视更新清单无效');
    }
    manifest = TvUpdateManifest.parse(json);
    available = manifest!.select(installed!);
    notifyListeners();
  }

  Future<String> download({
    required TvUpdateAsset asset,
    required CancelToken cancel,
    required ProgressCallback onProgress,
  }) async {
    if (!identical(asset, available)) {
      throw const FormatException('更新信息已变化，请重新检查');
    }
    final temp = await getTemporaryDirectory();
    final path =
        '${temp.path}/kazumitv-${asset.versionCode}-${asset.sha256.substring(0, 12)}.apk';
    await downloadUpdateFile(
      url: asset.url,
      filePath: path,
      expectedHash: asset.sha256,
      cancelToken: cancel,
      onReceiveProgress: onProgress,
    );
    if (cancel.isCancelled) throw cancel.cancelError!;
    if (await File(path).length() != asset.size) {
      await File(path).delete();
      throw const FormatException('安装包大小与更新清单不符');
    }
    await TvMode.channel.invokeMethod<void>('verifyTvUpdateApk', {
      'path': path,
      'versionCode': asset.versionCode,
    });
    return path;
  }

  Future<bool> canInstall() async =>
      await TvMode.channel.invokeMethod<bool>('canInstallTvUpdate') ?? false;

  Future<void> openInstallSettings() =>
      TvMode.channel.invokeMethod<void>('openTvUpdateInstallSettings');

  Future<void> install(String path, TvUpdateAsset asset) async {
    // Recheck immediately before opening the Android installer; a cached path
    // alone is not permission to install an arbitrary APK.
    await TvMode.channel.invokeMethod<void>('verifyTvUpdateApk', {
      'path': path,
      'versionCode': asset.versionCode,
    });
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw const FormatException('无法打开系统安装界面，请检查安装权限');
    }
  }
}
