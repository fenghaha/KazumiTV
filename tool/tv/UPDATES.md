# 电视版应用内更新与发布

电视更新只读取 `fenghaha/KazumiTV` 的正式 GitHub Release：
`https://github.com/fenghaha/KazumiTV/releases/latest/download/tv-update.json`。
源码与更新文件公开，不在 APK 中嵌入 GitHub token。上游官方更新器保留给普通构建；
显式 `KAZUMI_TV=true` 的电视构建统一进入自己的更新页，避免安装官方包。

## 用户操作

电视首页进入“设置 → 软件更新”。有更新时选择“下载更新”，下载及验证成功后选择
“安装更新”。首次需要允许 KazumiTV 安装应用；返回后在 Android 的安装界面确认。
这是有系统确认的覆盖升级，不能承诺普通应用可以静默安装。观看记录、规则、设置不清除。
启动时只检查一次；网络失败不弹错误打断首页，不在播放期间轮询或强制更新。

## 版本与匹配

- `pubspec.yaml` 的版本和规则 API 仍来自实际合入的上游，不为电视更新改写。
- `tool/tv/release.json` 中 `revision` 为电视修订；`androidVersionBase` 是独立、递增的
  Android 安装序号。现有上游 ABI 末位规则保留：ARM32 为 base×10+1，ARM64 为 base×10+2。
- 每次发布递增 Android 序号，即使上游语义版本不变。不能重复发布较小序号。
- 清单按已安装包名、真实设备支持的 ABI、编译时显式设备档、系统最低版本和实际 Android
  versionCode 选择唯一适配包。极米 `xgimi-z9x` 的预读策略不流入 generic 包。
- 只接受本仓库的 HTTPS Release APK，下载必须校验 SHA256 与大小；安装前通过 Android
  再核包名、更高的版本号和与当前应用一致的签名。不接受官方包或其他证书替代当前应用。

## 制作发布包

先按 AGENTS.md 执行上游契约、全量测试、分析与打包检查。使用已有的外置签名材料，
依次制作 `xgimi-z9x / android-arm` 和 `generic / android-arm64`，不并行占用构建机。

```bash
KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x tool/tv/build.sh --target-platform android-arm
KAZUMI_TV_DEVICE_PROFILE=generic tool/tv/build.sh --target-platform android-arm64
```

每个包构建完成后立即另存，避免后一次覆盖产物。然后运行 `prepare_release.py`，传入两包、
Android SDK 中的 aapt/apksigner、已安装版本的签名证书 SHA256 和独立输出目录。
脚本读取真实 APK 的包名、版本／ABI／签名，生成稳定文件名、清单与 SHA256SUMS；
校验失败即停止，不用预想的值冒充 APK 元数据。

发布前审查源码、历史和准备上传的文件；只上传两份公开 APK、`tv-update.json` 与
`SHA256SUMS`。使用标签 `v<上游版本>-tv-<电视修订>`，附清楚的功能、兼容与实测边界。
发布为正式最新版后，匿名下载清单与 APK，复核 SHA256；在真实设备完成一次应用内更新，
核实安装后的 Android 序号、签名、数据保留和实际桌面图标。

## 私人配置与素材

公开构建不传私人 `KAZUMI_DANMAKU_BASE_URL`、用户配置或凭据。旧私有构建若依赖编译
默认地址，可先使用相同证书的私有过渡包，在本机将既有有效选择落为设置，再升级公开包；
该过渡包不能上传 GitHub。用户明确选择的空值保留为空，现有自定义值不覆盖成别的地址。

新电视横幅以项目既有角色作参考，经 ImageGen 生成；用于取代旧电视横幅，不改写原图标
作者署名和权利说明，也不将原角色图稿重新声明为无条件自由素材。Aerial 使用应用横幅，
无需为新图标单独授权桌面服务或保存其管理能力 URL。

## 电视固件签名解析兼容性（2026-10-31）

极米 Android 13 实机的 `getPackageArchiveInfo` 仅传 `GET_SIGNING_CERTIFICATES` 时，
能读取包名与版本，但 `signingInfo` 为空；同时传入 `GET_SIGNATURES` 后会正常收集证书。
因此 API28 及以上同时请求两标志，比较仍只用 `signingInfo.apkContentsSigners` 的完整
SHA256 集合，要求非空且与当前安装完全相同；不会以旧证书历史或空集合放行。

可将 `tool/tv/android/SignatureProbe.java` 用 Android SDK android.jar 编译，经 d8 转为
classes.dex 并打成 jar，以 shell 的 app_process 对已公开 APK 复现。它不读取应用数据或
签名私钥，仅查询安装包证书，比较两种查询标志。第二个参数为 `mismatch` 时要求拒绝
不同证书；默认要求当前签名一致。测试只使用本项目包，不替换系统应用。

r5.8.2 首次正式验收暴露了上述问题；该版旧验证器无法自行更新，需要先同签名覆盖安装
修正版一次。r5.8.3 起保留兼容标志。普通 Android 安装确认、哈希、包名、版本和签名要求
均保留；不能通过跳过签名检查解决固件解析差异。
## 更新提醒与云端触发策略（2026-10-31）

TV 首页不再使用 SnackBar 的限时触控按钮。检查到更新后，使用显式 `TvTheme.dark`
Dialog，提供“稍后”“查看更新”，默认聚焦稍后，方向键／确认键可完成选择，返回或
Escape 关闭，并在关闭后恢复此前焦点；只有首页仍处于前台且未被其他路由覆盖时显示。
不在播放期间弹窗或轮询。

继承的 `.github/workflows/release.yaml` 原来匹配任意 push tag，TV 标签因此意外触发
iOS、Linux 等上游多平台发布。r5.8.2 的 Linux 打包将带 v 的 TV 标签直接作为 Debian
Version，导致失败邮件；这不是 UBT 已签名 TV APK 的构建结果。下游将该工作流改为
仅 workflow_dispatch；专门的 KazumiTV checks 也继续保持手动检查／可选开发包，不自动
上传没有个人签名的包。不得用关闭用户全局邮件通知来掩盖触发配置错误。