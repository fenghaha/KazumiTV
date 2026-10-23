# ARM32 HTTPS 读取性能修复

KazumiTV r5.4 为 armeabi-v7a 替换同版 libmpv 的 TLS 构建；上游版本/API、解码器、规则协议、其他 ABI 均保持。内核基础来自 media-kit 已固定的 Android v1.3.1，不升级 FFmpeg/mpv。

## 原因与证据

上游 `mbedtls.sh` 的 `make CFLAGS=-fPIC` 覆盖 mbedTLS Makefile 默认 `-O2`。极米 Z9X / Android 13 / ARM32 上，原库 AES-256-GCM 约 1.84 MB/s，恢复 -O2 的完整同版内核约 11.33 MB/s；原库独立 AVIO HTTPS 读取 8 MiB 为 5.220 秒、12.86 Mbps、CPU 4.228 秒。新完整内核同样校验证书、直连同一源读取 8 MiB 为 1.186 秒、56.60 Mbps、CPU 0.749 秒。该集平均约 26.33 Mbps，原库无法及时供数。关闭磁盘缓存、低内存模式和切换音频输出均未解决读取瓶颈。

临时飞牛 HTTP 中继只用于对照，已撤除；正式版本必须直接访问原 CDN，不包含中继地址/开关。TLS 证书策略、请求头和重定向逻辑沿用上游。

## 构建

Linux/UBT 构建依赖：Android NDK `28.2.13676358`、make、meson、ninja、pkg-config、autoconf/automake、libtool；Python 模块 jinja2/jsonschema。共享 UBT 一次只运行一个构建，原生编译最多 2 个任务；APK 继续使用一名 Gradle worker、2 GiB JVM、进程内 Kotlin、无持久 daemon。

```sh
python3 tool/tv/native/build_kernel.py \
  --work-dir /path/to/dedicated-libmpv-build \
  --sdk "$ANDROID_HOME"
# 产物：build/native/armeabi-v7a/libmpv.so 与 receipt.json
KAZUMI_TV_KEY_PROPERTIES=/private/signing/key.properties \
  bash tool/tv/build.sh --target-platform android-arm,android-arm64
```

构建脚本固定源 SHA、默认 flavor、NDK 和 TLS 补丁，并校验各依赖 SHA；单独的原生工作目录保留以便增量构建。NDK 工具名显式使用 llvm-nm/llvm-strip，并将该固定 libplacebo 子模块已有的 Vulkan 1.4.345 头文件提供给 mpv 的 pkg-config 检查，运行时仍链接 NDK 的原 Vulkan loader。`android/tv.gradle` 在合并 native libraries 后、strip 与签名前替换 ARM32 库，核对 `kernel.json` 已评审 SHA 和 ELF32/ARM 身份；缺失或不符即失败。签名仍由原私有 Gradle 配置完成，不复制/重签密钥。

可以通过 `KAZUMI_TV_ARM32_LIBMPV=/path/libmpv.so` 使用同一已验收二进制。新主机若重编得到不同 SHA，应核对源、工具链、补丁与实机结果，再更新 manifest，不自动承认新二进制已验收。`KAZUMI_TV_ALLOW_UPSTREAM_KERNEL=1` 仅供原版内核对照构建；带此变量的产物不能标记为 r5.4 性能修复已验收。非 TV flavor 不加载此覆盖层。

## 验证与回退

- `python3 -m unittest discover -s tool/tv/native -p 'test_*.py'` 验证 make 参数及补丁，包含引号回归。
- 提取最终 APK `lib/armeabi-v7a/libmpv.so` 核 SHA，检查包版本、ABI、原签名与 APK 对齐。
- 极米必须在原桥接 302 → HTTPS CDN、原 Wi-Fi 下验证读取速度、缓存、声音、快进和持续播放；微基准与 APK 构建不能替代设备验收。
- 回退使用既有同签名 r5.3 ARM32 包覆盖，不卸载/清数据；详细当次验收与产物见 KnowledgeHub 的 KazumiTV 开发与设备验收文档。

## 极米本次设备配置与验收边界

本次媒体为《东京喰种》第一季首集的 3840×2160 HEVC Main 10 / FLAC，极米 Android 13 / ARM32。TLS 修复后，原自动 `gpu + mediacodec-copy` 仍观察到大量渲染丢帧和约 5 秒声画差，因此仅在这台设备保存现有 `mediacodec_embed` 选项；没有全局改写自动选择逻辑或强制其他设备直通。该媒体的直通对照读取约 5–7 MB/s，缓存可增长到 250 秒以上，声画差约 0；海信、ARM64 和其他编码仍须分别验收。低内存设置保留“跟随网络”，未将 2 MiB 小缓存作为性能修复。

## 独立微基准

`benchmark_crypto.c` 对已固定的 mbedTLS 3.6.7 导出接口做 8 MiB AES-256-GCM 测量；`benchmark_reader.c` 使用内核的 AVIO 读取 8 MiB，不创建解码器或绘制弹幕，输出耗时、Mbps 与 CPU 秒。用上述 NDK 的 `armv7a-linux-androideabi24-clang -O2 -fPIE -pie <source.c> -ldl -o <binary>` 编译，推送到设备临时目录并赋可执行权限。参数分别为：

```text
benchmark_crypto <libmpv.so>
benchmark_reader <libmpv.so> <URL文本文件> <受信CA的PEM文件>
```

URL 放设备 0600 临时文件中，不进命令参数、日志或 Git；优先用原桥接媒体地址，按实际播放器 UA 解析重定向。读取基准显式开启证书校验、提供受信 CA，抑制可能包含媒体 URL 的 FFmpeg 日志。实验结束删除临时文件。微基准不代表完整设备播放或弹幕滚动验收。
