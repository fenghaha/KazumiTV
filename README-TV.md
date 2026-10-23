# KazumiTV

以 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 原版为基础的个人电视分支，面向海信电视与极米 Z9X 投影仪。大海报、分行浏览、可见的遥控焦点、原生 Android 输入法和可选手机扫码输入。旧 Carey-L/Kazumi-TV 与 Muse 补丁仅供历史参考，不是此仓库的父分支。

## 开发边界

- `lib/tv/` 保存独立电视展示层；数据和行为复用原版 controller、repository、规则引擎与播放器。原文件尽量只保留入口和展示切换；可选自建弹幕需要的四处明确扩展以 `tool/tv/upstream.json` 的精确哈希和理由单列，见 [弹幕接入说明](tool/tv/DANMAKU.md)。
- **不伪造客户端版本，不提高规则 API 等级，不绕过规则兼容检查。** `pubspec.yaml` 版本、`ApiEndpoints`、规则 JSON、嗅探及播放数据模型均随上游。
- `tool/tv/upstream.json` 记录已合入的真实上游提交、版本和 API；电视修订由 `KAZUMI_TV_REVISION` 单独表示。当前基线 `db5202611902fe67c449e0a53bc05c3a75b4e8b0`，Kazumi `2.4.1+20401`，API 9。
- Android TV 打包由 `android/tv.gradle` 与 flavor manifest 负责，仅 `KAZUMI_BUILD_TV=1` 时生效，原版无 flavor 构建入口保留。
- 应用名称 **KazumiTV**，application ID `com.fenghaha.kazumitv`。首次安装为独立应用；不假定能覆盖不同签名的第三方 TV 包，不在安装前删除旧数据。
- 不内置第三方播放源、媒体账号或弹弹凭据。Emby 桥接是独立工程，通过上游兼容规则接入。

## r5 播放返回

TV 播放页根部始终保护退出，加载中也生效。返回先结束进度编辑或收起菜单，这一次不计入退出；没有菜单时第一次返回提示“再按一次返回退出播放”，2 秒内再按才退出。菜单/弹窗操作取消确认，按住返回不累计；300 ms 内 key/system 配对事件只处理一次。保持已合入的自建弹幕支持，私有发布继续传默认服务 defines。实机结果以 KnowledgeHub 的极米 r5 记录为准。

## r4 遥控与订阅

- 规则入口统一到 TV 页面（含高级设置里的“规则管理”）。在“导入规则”直接输入或粘贴 HTTP/HTTPS 规则 JSON 地址，检查后确认导入；也可以扫码发送短链接，原 JSON/kazumi:// 导入继续可用。
- URL 导入保存来源，单条“更新订阅”或“更新已安装规则”按原链接拉取更高版本；一个链接可以返回规则对象或规则数组。失败、不兼容、同版/旧版不覆盖；更新不自动安装新增规则或恢复已移除规则。发布者需递增规则 `version`；商店 index、网页或其他订阅格式不支持。
- 来源映射位于现有 setting box 的 TV 自有键 `kazumitv.ruleSources.v1`，不改原版已安装规则格式；移除规则删除绑定，手动 JSON 重导入解除该规则绑定，改地址可用新链接重新导入。含能力参数的 URL 不写入日志或共享文档。
- 设置开关整行确认；选择菜单进入独立弹窗，返回取消并恢复焦点。同步卡片用纵向紧凑布局。TV 设置与播放器输入使用原生编辑，保留表单验证和数字过滤。
- 滑块/播放进度：确认进入、左右调节、上下离开，返回先结束调节。播放器按弹窗、进度调节、控制栏、播放页逐层返回。
- 实机验收和固定 APK/签名/测试记录以 KnowledgeHub `KazumiTV-开发与设备验收.md` 的 r4 节为准；播放源和弹幕匹配由独立桥接会话处理，不以界面测试代替媒体验收。

## r4-danmaku1 与当前接续入口（2026-10-24）

- 自建弹幕、真实分集 ID、Bangumi 别名和专用非日志网络客户端已合入主开发分支 `codex/kazumitv`；包含 r4 的订阅/设置/遥控修复。真实上游仍是 `db5202611902… / 2.4.1+20401 / API 9`，没有向官方上游 main 推送。
- 已交付包的功能代码为 `e87e09996f75d6dd18bb304a74a85989039d30e7`，293 项完整测试、11 项目标回归、静态分析与签名校验通过；之后的文档/分支对齐不代表重建过 APK。两种 ARM 包及清单保留在主工程 `build/releases/r4-danmaku1/`。
- 弹幕设置可填自建兼容 API；私有发布可用 `--dart-define=KAZUMI_DANMAKU_BASE_URL=...` 设置默认地址。该值必须在每次重建时明确传入，或安装后在设置页填写；没有内置默认地址的普通源码构建仍走官方端点，需要自己有效的官方凭据。真实家庭地址以 KnowledgeHub 专题为准，不硬编码进源码。
- Emby 桥接、danmu_api 部署与 AP 出站规则各自维护，运行事实见 KnowledgeHub `KazumiTV-Emby桥接.md`、`KazumiTV-弹幕服务与故障处理.md`；东京喰种四季源名、媒体跳转修复、弹幕服务与电视验收是不同状态。
- 主会话继续开发前核 `git status`、`git log -1`，读 [弹幕接入说明](tool/tv/DANMAKU.md) 并跑契约检查。当前 Mac/UBT 主工程均可接续；独立弹幕工作树保留为历史，不再作为并行写入端。设备画面/声音/弹幕时间轴仍待海信与极米分别验收。

## 构建

使用 `pubspec.yaml` 要求的 Flutter SDK、JDK 17 与 Android SDK/NDK。Flutter 版本随上游更新，不在 TV 脚本另锁一份。当前本机开发，UBT 的独立 Flutter 3.47.7 环境用于 Linux 构建；不要覆盖 Muse 的旧 SDK/工作区。

`tool/tv/build.sh` 默认使用单 Gradle worker、2 GiB JVM、Kotlin in-process 和非持久 daemon；显式 `GRADLE_OPTS` 可覆盖。测试与打包串行执行，避免共享 UBT 再次耗尽内存。

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

官方弹弹端点的凭据仍走上游 `DANDANAPI_APPID` / `DANDANAPI_KEY` 编译参数；可用私有配置文件通过 `tool/tv/build.sh --dart-define-from-file=/private/path/defines.json` 注入自己合法持有的凭据。没有凭据时应配置自己的兼容服务，不从原 APK 提取密钥。

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

`reviewedExtensions` 只允许已记录原因且 SHA256 完全一致的四处自建弹幕扩展。合并上游时逐处审查和回归后再更新相应哈希；未知文件或意外改动仍须失败，不能把本地 HEAD 登记为官方上游。

确认 APK、来源兼容与两台设备回归后再合回开发分支。TV 分支不自动下载/安装官方手机 APK；规则自身的商店、安装和更新机制继续复用上游。

## 设备验收

离线布局测试覆盖 960×540 与 1280×720 逻辑视口，不能代替设备验收。海信与极米各自记录 APK SHA、系统/ABI、显示密度、遥控键值与结果：

1. 首次启动、首页/搜索/日历/追番/历史切换，焦点清晰且自动滚入视野；进入详情返回恢复位置。
2. 确认进入原生编辑框，系统输入法实际收字；返回关闭/取消、完成后焦点恢复；扫码输入、取消和网络切换。
3. 规则商店/导入/版本不兼容提示，搜索、选源、选集、播放与历史恢复。
4. 播放中确认、快进/退、菜单与返回；对话框和输入法打开时播放器不吞键。
5. 各设备实际解码、声音、长播、弹幕和季/集对应；这些需独立实测，构建通过不表示完成。

项目继承上游 GPL-3.0，许可证及原 README 保留。界面预览测试中的示例番剧与占位海报只用于布局验证，不打包成真实推荐数据。
