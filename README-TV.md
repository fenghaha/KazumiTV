# KazumiTV

以 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 原版为基础的个人电视分支，面向海信电视与极米 Z9X 投影仪。大海报、分行浏览、可见的遥控焦点、原生 Android 输入法和可选手机扫码输入。旧 Carey-L/Kazumi-TV 与 Muse 补丁仅供历史参考，不是此仓库的父分支。

## 开发边界

- `lib/tv/` 保存独立电视展示层；数据和行为复用原版 controller、repository、规则引擎与播放器。原文件只保留入口和展示切换。
- **不伪造客户端版本，不提高规则 API 等级，不绕过规则兼容检查。** `pubspec.yaml` 版本、`ApiEndpoints`、规则 JSON、嗅探及播放数据模型均随上游。
- `tool/tv/upstream.json` 记录已合入的真实上游提交、版本和 API；电视修订由 `KAZUMI_TV_REVISION` 单独表示。当前基线 `db5202611902fe67c449e0a53bc05c3a75b4e8b0`，Kazumi `2.4.1+20401`，API 9。
- Android TV 打包由 `android/tv.gradle` 与 flavor manifest 负责，仅 `KAZUMI_BUILD_TV=1` 时生效，原版无 flavor 构建入口保留。
- 应用名称 **KazumiTV**，application ID `com.fenghaha.kazumitv`。首次安装为独立应用；不假定能覆盖不同签名的第三方 TV 包，不在安装前删除旧数据。
- 不内置第三方播放源、媒体账号或弹弹凭据。Emby 桥接是独立工程，通过上游兼容规则接入。

## 构建

使用 `pubspec.yaml` 要求的 Flutter SDK、JDK 17 与 Android SDK/NDK。Flutter 版本随上游更新，不在 TV 脚本另锁一份。当前本机开发，UBT 的独立 Flutter 3.47.7 环境用于 Linux 构建；不要覆盖 Muse 的旧 SDK/工作区。

```bash
flutter pub get
python3 tool/tv/check_upstream.py
flutter analyze --no-fatal-infos
flutter test --concurrency=1
tool/tv/build.sh
```

APK 位于 `build/app/outputs/flutter-apk/app-{ABI}-livingroom-release.apk`。分别保留 armeabi-v7a、arm64-v8a 与 x86_64 包；安装前查询设备真实 ABI / Android 版本，不能按品牌推断。

默认沿用上游开发签名。长期分发可将签名配置放在仓库之外，设置 `KAZUMI_TV_KEY_PROPERTIES` 为其绝对路径；配置键为 `storeFile`（绝对路径）、`storePassword`、`keyAlias`、`keyPassword`，私钥和密码不得进 Git。发布时固定签名，升级同一 application ID 才能保留数据。

2026-10-23 交付的 r1 已在 UBT 使用固定私有签名构建，两种 ARM 包均通过证书校验；它们不是上述未配置签名变量的开发包。后续覆盖升级必须继续指定同一签名配置。实际私有文件位置、252 项测试结果、APK 哈希及两台设备待验状态记录在 KnowledgeHub 的 `KazumiTV-开发与设备验收.md`；APK 的功能源码提交是 `0fc86f1b958795fddcab94bd30172dba78dd4116`。

弹弹凭据仍走上游 `DANDANAPI_APPID` / `DANDANAPI_KEY` 编译参数；可用私有配置文件通过 `tool/tv/build.sh --dart-define-from-file=/private/path/defines.json` 注入自己合法持有的凭据。没有凭据的构建不承诺在线弹幕可用，也不从原 APK 提取密钥。

Bangumi 镜像的受保护搜索也使用上游 `KAZUMI_APPID` / `KAZUMI_KEY`。个人构建没有这些凭据时，TV 首次欢迎仅将尚未设置的番剧访问模式选为公共 API 直连，避免默认镜像搜索带空签名；明确选择/导入的设置保留，可在网络设置改为 ECH。没有修改上游网络协议或签名逻辑。

## 合入上游

先提交/保全本地工作，随后在临时集成分支做普通 merge，不覆写长期分支历史：

```bash
git fetch upstream
git switch -c integrate/kazumi-next
git merge upstream/main
python3 tool/tv/record_upstream.py --ref upstream/main
python3 tool/tv/check_upstream.py
flutter pub get
flutter analyze --no-fatal-infos
flutter test --concurrency=1
tool/tv/build.sh
```

`record_upstream.py` 要求该上游提交已是 HEAD 的祖先，只记录实际合入版本，不修改应用版本。`check_upstream.py` 对比规则/网络/数据/嗅探/播放服务与该基线，并核版本/API，发现意外分叉即失败。新上游若调整 controller 或路由接口，适配 `lib/tv/` 的调用方；不能通过把 API 号调大来消除不兼容提示。

确认 APK、来源兼容与两台设备回归后再合回开发分支。TV 分支不自动下载/安装官方手机 APK；规则自身的商店、安装和更新机制继续复用上游。

## 设备验收

离线布局测试覆盖 960×540 与 1280×720 逻辑视口，不能代替设备验收。海信与极米各自记录 APK SHA、系统/ABI、显示密度、遥控键值与结果：

1. 首次启动、首页/搜索/日历/追番/历史切换，焦点清晰且自动滚入视野；进入详情返回恢复位置。
2. 确认进入原生编辑框，系统输入法实际收字；返回关闭/取消、完成后焦点恢复；扫码输入、取消和网络切换。
3. 规则商店/导入/版本不兼容提示，搜索、选源、选集、播放与历史恢复。
4. 播放中确认、快进/退、菜单与返回；对话框和输入法打开时播放器不吞键。
5. 各设备实际解码、声音、长播、弹幕和季/集对应；这些需独立实测，构建通过不表示完成。

项目继承上游 GPL-3.0，许可证及原 README 保留。界面预览测试中的示例番剧与占位海报只用于布局验证，不打包成真实推荐数据。
