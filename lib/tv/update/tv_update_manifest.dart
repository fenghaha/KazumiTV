const tvUpdateRepository = 'https://github.com/fenghaha/KazumiTV';
const tvUpdateManifestUrl =
    '$tvUpdateRepository/releases/latest/download/tv-update.json';
const tvUpdatePackage = 'com.fenghaha.kazumitv';

/// The installed Android version code, not the upstream semantic version,
/// decides whether this downstream build can actually replace the app.
class TvInstalledBuild {
  const TvInstalledBuild({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.abis,
    required this.sdk,
    required this.profile,
  });

  final String packageName;
  final int versionCode;
  final String versionName;
  final List<String> abis;
  final int sdk;
  final String profile;
}

class TvUpdateAsset {
  const TvUpdateAsset({
    required this.abi,
    required this.profile,
    required this.versionCode,
    required this.minSdk,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final String abi;
  final String profile;
  final int versionCode;
  final int minSdk;
  final String url;
  final String sha256;
  final int size;

  factory TvUpdateAsset.parse(Map<String, dynamic> json) {
    final url = Uri.tryParse(json['url'] as String? ?? '');
    final hash = json['sha256'] as String? ?? '';
    final size = json['size'];
    final code = json['versionCode'];
    final minSdk = json['minSdk'];
    final profile = json['profile'];
    final abi = json['abi'];
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        !url.path.startsWith('/fenghaha/KazumiTV/releases/download/') ||
        !url.path.endsWith('.apk') ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size <= 0 ||
        size > 512 * 1024 * 1024 ||
        code is! int ||
        code <= 0 ||
        minSdk is! int ||
        minSdk < 24 ||
        !{'armeabi-v7a', 'arm64-v8a', 'x86_64'}.contains(abi) ||
        !{'generic', 'xgimi-z9x', 'hisense-mt9655'}.contains(profile)) {
      throw const FormatException('电视更新文件信息无效');
    }
    return TvUpdateAsset(
      abi: abi as String,
      profile: profile as String,
      versionCode: code,
      minSdk: minSdk,
      url: url.toString(),
      sha256: hash.toLowerCase(),
      size: size,
    );
  }
}

class TvUpdateManifest {
  const TvUpdateManifest({
    required this.version,
    required this.revision,
    required this.notes,
    required this.assets,
  });

  final String version;
  final String revision;
  final String notes;
  final List<TvUpdateAsset> assets;

  factory TvUpdateManifest.parse(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    final version = json['version'];
    final revision = json['revision'];
    final notes = json['notes'];
    if (json['schema'] != 1 ||
        json['package'] != tvUpdatePackage ||
        version is! String ||
        version.isEmpty ||
        version.length > 40 ||
        revision is! String ||
        revision.isEmpty ||
        revision.length > 80 ||
        notes is! String ||
        notes.length > 16000 ||
        rawAssets is! List ||
        rawAssets.isEmpty ||
        rawAssets.length > 12) {
      throw const FormatException('电视更新清单无效');
    }
    final assets = rawAssets
        .map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('电视更新文件信息无效');
          }
          return TvUpdateAsset.parse(raw);
        })
        .toList(growable: false);
    final keys = assets.map((a) => '${a.profile}/${a.abi}').toSet();
    if (keys.length != assets.length) {
      throw const FormatException('电视更新清单含重复设备包');
    }
    return TvUpdateManifest(
      version: version,
      revision: revision,
      notes: notes,
      assets: assets,
    );
  }

  TvUpdateAsset? select(TvInstalledBuild installed) {
    if (installed.packageName != tvUpdatePackage) return null;
    for (final abi in installed.abis) {
      for (final asset in assets) {
        if (asset.abi == abi &&
            asset.profile == installed.profile &&
            asset.versionCode > installed.versionCode &&
            asset.minSdk <= installed.sdk) {
          return asset;
        }
      }
    }
    return null;
  }
}
