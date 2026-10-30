import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/update/tv_update_manifest.dart';

Map<String, dynamic> asset({
  String abi = 'armeabi-v7a',
  String profile = 'xgimi-z9x',
  int code = 20402091,
  int minSdk = 24,
}) => {
  'abi': abi,
  'profile': profile,
  'versionCode': code,
  'minSdk': minSdk,
  'url':
      '$tvUpdateRepository/releases/download/v2.4.2-tv-r5.8.1/KazumiTV-$abi.apk',
  'sha256': 'a' * 64,
  'size': 32000000,
};

Map<String, dynamic> manifest([List<Map<String, dynamic>>? assets]) => {
  'schema': 1,
  'package': tvUpdatePackage,
  'version': '2.4.2',
  'revision': 'r5.8.1',
  'notes': '电视横幅与应用内更新',
  'assets': assets ?? [asset()],
};

TvInstalledBuild installed({
  int code = 20402081,
  List<String> abis = const ['armeabi-v7a', 'armeabi'],
  String profile = 'xgimi-z9x',
  String package = tvUpdatePackage,
  int sdk = 33,
}) => TvInstalledBuild(
  packageName: package,
  versionCode: code,
  versionName: '2.4.2',
  abis: abis,
  sdk: sdk,
  profile: profile,
);

void main() {
  test(
    'TV revision updates even when upstream semantic version is unchanged',
    () {
      final m = TvUpdateManifest.parse(manifest());
      expect(m.version, installed().versionName);
      expect(m.select(installed())!.versionCode, 20402091);
    },
  );
  test('already installed or older releases cannot downgrade', () {
    final m = TvUpdateManifest.parse(manifest());
    expect(m.select(installed(code: 20402091)), isNull);
    expect(m.select(installed(code: 20402101)), isNull);
  });
  test('never replace an official upstream package', () {
    expect(
      TvUpdateManifest.parse(manifest())
          .select(installed(package: 'com.predidit.kazumi')),
      isNull,
    );
    expect(
      () => TvUpdateManifest.parse({
        ...manifest(),
        'package': 'com.predidit.kazumi',
      }),
      throwsFormatException,
    );
  });
  test('device profile is exact, not inferred from RAM or display name', () {
    expect(
      TvUpdateManifest.parse(manifest()).select(installed(profile: 'generic')),
      isNull,
    );
  });
  test('ARM32 cannot select an ARM64 package', () {
    expect(
      TvUpdateManifest.parse(manifest([asset(abi: 'arm64-v8a')]))
          .select(installed()),
      isNull,
    );
  });
  test('select supported ABI in platform preference order', () {
    final m = TvUpdateManifest.parse(
      manifest([
        asset(profile: 'generic'),
        asset(abi: 'arm64-v8a', profile: 'generic', code: 20402092),
      ]),
    );
    expect(
      m
          .select(
            installed(profile: 'generic', abis: ['arm64-v8a', 'armeabi-v7a']),
          )!
          .abi,
      'arm64-v8a',
    );
  });
  test('unsupported Android minimum is not offered', () {
    expect(
      TvUpdateManifest.parse(manifest([asset(minSdk: 34)])).select(installed()),
      isNull,
    );
  });
  for (final url in [
    'http://github.com/fenghaha/KazumiTV/releases/download/v1/a.apk',
    'https://github.com/Predidit/Kazumi/releases/download/v1/a.apk',
    'https://github.com.evil.example/fenghaha/KazumiTV/releases/download/v1/a.apk',
    'https://other.example/a.apk',
    '$tvUpdateRepository/releases/download/v1/a.apk?token=unexpected',
  ]) {
    test(
      'reject update outside the exact public release destination: $url',
      () {
        expect(
          () => TvUpdateManifest.parse(
            manifest([
              {...asset(), 'url': url},
            ]),
          ),
          throwsFormatException,
        );
      },
    );
  }
  test('reject absent or malformed integrity and size fields', () {
    for (final change in [
      {'sha256': ''},
      {'sha256': 'not-a-hash'},
      {'size': 0},
      {'size': 600 * 1024 * 1024},
      {'versionCode': '20402091'},
      {'minSdk': 0},
    ]) {
      expect(
        () => TvUpdateManifest.parse(
          manifest([
            {...asset(), ...change},
          ]),
        ),
        throwsFormatException,
      );
    }
  });
  test('reject ambiguous duplicate packages', () {
    expect(
      () => TvUpdateManifest.parse(manifest([asset(), asset()])),
      throwsFormatException,
    );
  });
  test('reject malformed schema and missing revision', () {
    for (final change in [
      {'schema': 2},
      {'revision': ''},
      {'assets': []},
    ]) {
      expect(
        () => TvUpdateManifest.parse({...manifest(), ...change}),
        throwsFormatException,
      );
    }
  });
}
