# KazumiTV

**为遥控器设计的番剧客户端。**

基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 的 Android TV 适配分支。
使用大海报、横向内容架和清晰的焦点，让电视与投影仪上的浏览、搜索和播放更顺手。
规则解析与播放能力沿用上游，电视交互和设备适配在本项目中独立维护。

[下载电视版](https://github.com/fenghaha/KazumiTV/releases/latest) · [使用与开发说明](README-TV.md) · [更新与发布](tool/tv/UPDATES.md) · [反馈问题](https://github.com/fenghaha/KazumiTV/issues)

<p align="center">
  <img src="android/app/src/livingroom/res/drawable/tv_banner_art.png" alt="KazumiTV — 电视与投影仪上的番剧客户端" width="800">
</p>

## 电视上能做什么

- **用遥控器浏览。** 首页推荐、搜索、放送日历、追番列表和历史记录使用电视布局；方向键移动，确认键进入，返回键逐级退出。
- **搜索与管理规则。** 支持导入规则、订阅与更新，沿用 Kazumi 的规则格式与兼容性检查。首次安装不预装播放源。
- **在手机上输入。** 电视原生输入框可使用系统输入法，也可通过同一局域网的手机辅助输入，减少遥控器逐字输入的负担。
- **播放与弹幕。** 保留上游播放器、硬件解码、选集、字幕和播放设置；提供遥控器控制条、进度调节与弹幕设置。
- **保留观看进度。** 继续使用追番、历史记录与上游同步功能，支持在设置中配置 WebDAV。
- **在应用内更新。** 从本仓库检查并下载适配设备的电视版 APK，验证文件与签名后调用 Android 安装界面，覆盖升级保留数据。
- **适配电视桌面。** 横向应用封面用于 Aerial 等 Android TV 桌面。

本项目是独立的下游电视适配版，**不是 Predidit 发布的官方客户端**。

## 下载与安装

进入 [Releases](https://github.com/fenghaha/KazumiTV/releases/latest)，选择对应安装包：

| 安装包标识 | 用途 |
|---|---|
| `xgimi-z9x-armeabi-v7a` | 本项目验证的极米 Z9X，Android 13／32 位 ARM，包含该机型的专用播放调优 |
| `generic-arm64-v8a` | 通用 64 位 ARM 电视版；本项目主要在海信 E5S Pro 100 英寸、Android 14 上验证 |

**按实际系统 ABI 选包。** 同品牌、同系列并不保证位数与固件相同；其他机型尚未逐一验证。
极米专用策略不会因为设备内存较小而自动套用到通用包。

1. 下载匹配的 APK，用电视现有的安装方式完成安装。
2. 首次打开后导入你有权使用的规则，按需要配置弹幕、同步等服务。
3. 后续进入 **设置 → 软件更新** 检查、下载和安装新版。

已有本项目版本时直接覆盖安装，保持应用标识与签名一致。不要为升级而卸载或清除数据。
普通 Android 应用不能保证静默安装，最终仍需在系统界面确认；首次可能需要允许 KazumiTV 安装应用。

公开安装包不包含私人服务器地址、账号、GitHub token 或签名私钥。自建弹幕与 WebDAV 等私人服务请在应用内自行配置。

## 关于更新

电视版只使用 [fenghaha/KazumiTV 的正式发布](https://github.com/fenghaha/KazumiTV/releases)，
不会用上游官方 APK 替换当前电视版。启动时检查一次，有新版可进入更新页；不会在播放期间持续轮询或强制安装。

下载会按应用标识、设备 ABI、显式设备档和 Android 版本匹配，检查 SHA256、大小及当前应用签名。
电视修订使用独立的递增 Android 安装序号，因此上游版本没有变化时，也可以更新电视适配功能。
具体流程见 [更新与发布说明](tool/tv/UPDATES.md)。

## 适用范围与已知边界

- 面向 Android 电视与投影仪；不是 LG webOS、三星 Tizen 或鸿蒙原生电视应用。
- 目前主要验证极米 Z9X 与海信 E5S Pro 100 英寸。安装成功不等于所有遥控器、固件、解码器与信号源都通过验收。
- 不提供内置影视资源或账号；规则和媒体来源由使用者自行选择。播放与弹幕可用性取决于规则、来源、网络和设备。
- 低配设备的性能改善按实测保留，不以单次帧率或空闲内存承诺所有内容都流畅。
- 开发、编译、已发布和实机验收是不同状态；每个版本的具体结果以 Release 说明为准。

## 从源码构建

使用 Flutter **3.47.8**、JDK 17 与匹配的 Android SDK／构建工具。
电视打包是显式开启的覆盖层，普通上游构建保持原有行为。

```bash
flutter pub get
python3 tool/tv/check_upstream.py
flutter analyze --no-fatal-infos
flutter test --concurrency=1

# 通用 ARM64 电视版
KAZUMI_TV_DEVICE_PROFILE=generic tool/tv/build.sh --target-platform android-arm64

# 极米 Z9X ARM32 专用版
KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x tool/tv/build.sh --target-platform android-arm
```

ARM32 包需要按 [原生内核说明](tool/tv/native/README.md) 准备经过校验的 libmpv；
不能为省事跳过内核校验，或把实验性播放器、代理和中继带入正式包。

正式发布沿用外置签名材料，通过 `KAZUMI_TV_KEY_PROPERTIES` 指定配置文件；密钥和私人构建参数不能提交。
修改 `tool/tv/release.json` 的电视修订与 Android 安装序号，完成验证后使用
[`prepare_release.py`](tool/tv/prepare_release.py) 生成两种 APK 对应的更新清单和校验文件。
共享构建机按顺序运行测试与构建，不并行叠加；详细约定见 [AGENTS.md](AGENTS.md)。

## 代码结构

| 目录 | 职责 |
|---|---|
| `lib/tv/` | 电视布局、遥控输入、焦点导航、设备策略与电视更新 |
| `android/app/src/livingroom/`、`android/tv.gradle` | 电视包标识、横幅和打包覆盖层 |
| `tool/tv/` | 上游契约检查、设备与发布说明、构建工具 |
| `test/tv_*` | 电视交互、规则适配与设备策略回归 |
| 其余上游目录 | 尽量保留 Kazumi 的原有结构与职责 |

欢迎通过 Issue 反馈机型、系统版本、应用版本、复现步骤与可公开的截图。
请不要上传账号、媒体认证链接、私人服务地址、令牌或完整诊断日志。

## 上游、许可与致谢

本项目基于 **[Predidit/Kazumi](https://github.com/Predidit/Kazumi)**，感谢上游作者与贡献者。
代码沿用 **[GPL-3.0](LICENSE)**；下游修改保留上游版本、规则 API 和原有许可说明。

原 Kazumi 图标来自 **[Yuquanaaa](https://www.pixiv.net/users/66219277)**，原图版权归原作者；
上游说明的图标使用授权不等于该素材可以自由复制、修改或再分发。
本项目电视横幅以既有角色为参考，经 ImageGen 生成，保留原图标的作者署名与权利说明。
内嵌 **Mi Sans** 字体由 Xiaomi 开发，遵守其相应许可。

同时感谢 Flutter、media-kit／mpv、Bangumi、弹弹play、Hive、WebDAV 及上游列出的其他开源项目与服务。
软件与资料来源的使用应遵守相关许可和所在地法律。
