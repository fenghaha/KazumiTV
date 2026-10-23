#!/usr/bin/env python3
"""Rebuild the pinned ARM32 kernel with optimized TLS, in a separate workspace."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent

def run(*args, cwd=None, env=None):
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)

def capture(*args, cwd=None):
    return subprocess.check_output([str(a) for a in args], cwd=cwd, text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, default=os.environ.get('ANDROID_HOME'))
    parser.add_argument('--output', type=Path, default=HERE.parents[2] / 'build/native/armeabi-v7a')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    spec = json.loads((HERE / 'kernel.json').read_text())
    if args.sdk is None:
        parser.error('--sdk or ANDROID_HOME is required')
    sdk = args.sdk.expanduser().resolve()
    if not (sdk / 'ndk' / spec['ndk']).is_dir():
        parser.error('Install the pinned Android NDK ' + spec['ndk'])
    if not 1 <= args.jobs <= 2:
        parser.error('Use 1 or 2 native build workers on the shared build host')
    for tool in ['git', 'make', 'meson', 'ninja', 'pkg-config', 'autoreconf', 'libtoolize']:
        if not shutil.which(tool):
            parser.error('Missing build tool: ' + tool)
    work = args.work_dir.expanduser().resolve()
    if not work.exists():
        work.parent.mkdir(parents=True, exist_ok=True)
        run('git', 'clone', '--depth', '1', '--branch', spec['tag'], spec['repository'], work)
    if capture('git', 'rev-parse', 'HEAD', cwd=work) != spec['commit']:
        parser.error('Native workspace is not at the pinned upstream commit')
    source = work / 'buildscripts'
    patch = HERE / spec['patch']
    already = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=work, capture_output=True).returncode == 0
    if not already:
        run('git', 'apply', '--check', patch, cwd=work)
        run('git', 'apply', patch, cwd=work)
    depinfo = source / 'include/depinfo.sh'
    text = depinfo.read_text()
    refs = dict(re.findall(r'^(v_\w+|sha_\w+)=(\S+)$', text, re.M))
    # Exact SHAs are taken from the pinned upstream catalog; GitHub mirrors
    # retain upstream commit identities. Only default-flavor dependencies.
    deps = [
        ('mbedtls', 'Mbed-TLS/mbedtls', 'sha_mbedtls'),
        ('dav1d', 'videolan/dav1d', 'sha_dav1d'),
        ('libxml2', 'GNOME/libxml2', 'sha_libxml2'),
        ('ffmpeg', 'FFmpeg/FFmpeg', 'v_ffmpeg'),
        ('freetype', 'freetype/freetype', 'sha_freetype'),
        ('fribidi', 'fribidi/fribidi', 'sha_fribidi'),
        ('harfbuzz', 'harfbuzz/harfbuzz', 'sha_harfbuzz'),
        ('libass', 'libass/libass', 'sha_libass'),
        ('lcms2', 'mm2/Little-CMS', 'sha_lcms2'),
        ('libplacebo', 'haasn/libplacebo', 'v_libplacebo'),
        ('mpv', 'mpv-player/mpv', 'v_mpv'),
    ]
    (source / 'deps').mkdir(exist_ok=True)
    for name, repository, ref in deps:
        path = source / 'deps' / name
        if not (path / '.git').exists():
            path.mkdir(exist_ok=True)
            run('git', 'init', '-q', path)
            run('git', 'remote', 'add', 'origin', 'https://github.com/' + repository + '.git', cwd=path)
            run('git', 'fetch', '--depth', '1', 'origin', refs[ref], cwd=path)
            run('git', 'checkout', '--detach', 'FETCH_HEAD', cwd=path)
        if capture('git', 'rev-parse', 'HEAD', cwd=path) != refs[ref]:
            parser.error('Unexpected dependency commit: ' + name)
        run('git', 'submodule', 'update', '--init', '--recursive', '--depth', '1', cwd=path)
    # The pinned libplacebo already provides newer Vulkan headers than NDK 28.
    # Export their pkg-config metadata for mpv, using the NDK's existing loader.
    prefix = source / 'prefix/armeabi-v7a'
    prefix.mkdir(parents=True, exist_ok=True)
    for name in ['usr', 'local']:
        alias = prefix / name
        if not alias.exists():
            alias.symlink_to('.', target_is_directory=True)
    headers = source / 'deps/libplacebo/3rdparty/Vulkan-Headers/include'
    shutil.copytree(headers, prefix / 'include', dirs_exist_ok=True)
    core = (headers / 'vulkan/vulkan_core.h').read_text()
    patch_version = re.search(r'#define VK_HEADER_VERSION (\d+)', core).group(1)
    pc = prefix / 'lib/pkgconfig'
    pc.mkdir(parents=True, exist_ok=True)
    (pc / 'vulkan.pc').write_text(
        'Name: Vulkan\nDescription: NDK loader with pinned libplacebo headers\n'
        f'Version: 1.4.{patch_version}\nLibs: -lvulkan\nCflags: -I/usr/local/include\n')
    for dependency in sorted((source / 'patches').iterdir()):
        for item in sorted(dependency.glob('*.patch')):
            path = source / 'deps' / dependency.name
            applied = subprocess.run(['git', 'apply', '--reverse', '--check', str(item)], cwd=path, capture_output=True).returncode == 0
            if not applied:
                run('git', 'apply', '--check', item, cwd=path)
                run('git', 'apply', item, cwd=path)
    # Upstream scripts expect a local SDK symlink. Keep host paths out of Git.
    sdk_link = source / 'sdk/android-sdk-linux'
    sdk_link.parent.mkdir(exist_ok=True)
    if not sdk_link.exists():
        sdk_link.symlink_to(sdk, target_is_directory=True)
    if sdk_link.resolve() != sdk:
        parser.error('Native workspace points to another Android SDK')
    depinfo.write_text(re.sub(r'^v_ndk=.*$', 'v_ndk=' + spec['ndk'], text, flags=re.M))
    shader = source / 'deps/shaderc'
    shader.mkdir(exist_ok=True)
    (shader / 'README').write_text('Build shaderc from the pinned Android NDK sources.\n')
    ffmpeg = (source / 'flavors/default.sh').read_text()
    (source / 'scripts/ffmpeg.sh').write_text(ffmpeg.replace(
        '--ranlib=$RANLIB', '--ranlib=$RANLIB --nm=llvm-nm --strip=llvm-strip'))
    driver = source / 'build.sh'
    driver.write_text(driver.read_text().replace('sudo chmod +x', 'chmod +x'))
    for script in (source / 'scripts').glob('*.sh'):
        script.chmod(script.stat().st_mode | 0o111)
    environment = dict(os.environ, cores=str(args.jobs))
    run('bash', '-e', 'build.sh', '--arch', 'armv7l', cwd=source, env=environment)
    library = source / 'prefix/armeabi-v7a/lib/libmpv.so'
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(library, output / 'libmpv.so')
    receipt = dict(repository=spec['repository'], commit=spec['commit'], ndk=spec['ndk'],
                   abi='armeabi-v7a', patch_sha256=digest(patch), sha256=digest(output / 'libmpv.so'))
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))

if __name__ == '__main__':
    main()
