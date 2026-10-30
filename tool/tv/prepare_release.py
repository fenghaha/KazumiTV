#!/usr/bin/env python3
"""Prepare only explicitly reviewed APKs and a strict, credential-free TV feed."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xgimi-apk', type=pathlib.Path, required=True)
    parser.add_argument('--generic-apk', type=pathlib.Path, required=True)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--apksigner', required=True)
    parser.add_argument('--expected-signer-sha256', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    release = json.loads((root / 'tool/tv/release.json').read_text())
    version = re.search(r'^version:\s*([^+\s]+)',
                        (root / 'pubspec.yaml').read_text(), re.M)[1]
    tag = f'v{version}-tv-{release["revision"]}'
    expected_signer = args.expected_signer_sha256.lower().replace(':', '')
    if not re.fullmatch(r'[a-f0-9]{64}', expected_signer):
        raise ValueError('Expected signer must be a SHA256 fingerprint')
    args.output.mkdir(parents=True, exist_ok=True)
    assets = []
    for path, profile, abi, suffix in [
        (args.xgimi_apk, 'xgimi-z9x', 'armeabi-v7a', 1),
        (args.generic_apk, 'generic', 'arm64-v8a', 2),
    ]:
        badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(path)], text=True)
        package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
        if not package or package[1] != 'com.fenghaha.kazumitv' or package[3] != version:
            raise ValueError('Unexpected package identity')
        code = int(package[2])
        if code != release['androidVersionBase'] * 10 + suffix:
            raise ValueError('Unexpected TV install sequence')
        native = re.search(r'^native-code:\s*(.+)$', badging, re.M)
        if not native or re.findall(r"'([^']+)'", native[1]) != [abi]:
            raise ValueError('Unexpected APK ABI')
        signing = subprocess.check_output(
            [args.apksigner, 'verify', '--print-certs', str(path)], text=True)
        signer = re.search(r'^Signer #1 certificate SHA-256 digest:\s*(\w+)', signing, re.M)
        if not signer or signer[1].lower() != expected_signer:
            raise ValueError('APK does not use the existing private signing key')
        name = f'KazumiTV-{version}-{release["revision"]}-{profile}-{abi}.apk'
        target = args.output / name
        shutil.copyfile(path, target)
        assets.append({
            'profile': profile, 'abi': abi, 'versionCode': code, 'minSdk': 24,
            'url': f'https://github.com/fenghaha/KazumiTV/releases/download/{tag}/{name}',
            'sha256': hashlib.file_digest(target.open('rb'), 'sha256').hexdigest(),
            'size': target.stat().st_size,
        })
    manifest = {'schema': 1, 'package': 'com.fenghaha.kazumitv',
                'version': version, 'revision': release['revision'],
                'notes': '新增电视横幅；支持检查、下载、校验并安装本项目电视版更新。保留原有设置与观看记录。',
                'assets': assets}
    (args.output / 'tv-update.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    files = [args.output / a['url'].rsplit('/', 1)[1] for a in assets]
    files.append(args.output / 'tv-update.json')
    (args.output / 'SHA256SUMS').write_text(''.join(
        f'{hashlib.file_digest(p.open("rb"), "sha256").hexdigest()}  {p.name}\n' for p in files))
    print(json.dumps({'tag': tag, 'assets': len(assets), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
