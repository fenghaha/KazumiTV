# 可选自建弹幕适配（2026-10-24）

用户实测多个番剧弹幕全部失败；当前个人构建没有官方弹弹play AppId/Key，
用空凭据实测 API 返回 403、`X-Error-Message: Missing Authentication Headers`，
Swagger 页面 200。BiliBili/Gamer 开关原来只是筛选官方接口聚合结果，不是独立抓取。

用户没有自己申请的凭据，要求验证 My-Kazumi-TV 提到的自建服务。
参考其可配置地址思路，但保留官方 Kazumi 主线，不整合其他电视分支。
测试引擎 huangxd-/danmu_api 固定 `5ef63a01bae7c4bad4dcd7bafbbcdcf33aa82564`。
Misaka 更适合需要持久弹幕库、元数据与 Emby Webhook 的后续阶段，本轮选按需服务。

## 接入

- 弹幕设置新增“弹幕服务器”，使用电视原生输入/二维码共用控件；留空恢复官方。
- 私有构建也可使用 `--dart-define=KAZUMI_DANMAKU_BASE_URL=...` 配置默认值。
  源码不包含家庭地址或能力 URL。不得把真实凭据写进此文档、日志或仓库。
- 官方路径、规则解析、版本、API 级别不变。自建地址不发送官方应用签名。
  自建 HTTP 客户端关闭 URL 日志，异常不携带含 token 的基地址。
- 自建服务不一定支持 `/bangumi/bgmtv/{id}`：先取当前 Bangumi 名称再搜索，
  只选名称精确且唯一的季/版本；歧义返回未匹配，保留手动选择。
- 自建的实际分集 ID 来自番剧详情，不使用官方“番剧 ID + 四位集号”约定。
  明确集号优先；旧版无集号的有序列表按位置选择且检查边界。
- 小写 `bilibili1`、`bahamut` 标签适配现有来源开关；不改上游弹幕模型或绘制逻辑。

## 上游合入边界

此修复确实需要 4 个上游文件的窄改动：danmaku API、认证客户端、Dio 工厂和设置键。
因此 `tool/tv/upstream.json` 保留真实已合入的 upstream commit、版本和 API，
另列 `reviewedExtensions` 原因和精确 SHA256；检查器只接受这批已记录内容，
其他受保护文件变化或这些文件后续变化仍失败。不能用本地 HEAD 冒充 upstream。

本分支从 r3 `37b09b35` 独立建立，之后在本分支合入已完成的 r4
`fcf64508582543fb7a06062dee78df3a66de0828`，未修改另一会话 r4 工作区。
最终编译提交 `e87e09996f75d6dd18bb304a74a85989039d30e7`，包为 `r4-danmaku1`，
保留 r4 的订阅、设置和播放器焦点改动。早期 r3 构建只是阶段候选。

2026-10-24 用户要求统一主分支与交接后，本扩展已快进合入主开发分支
`codex/kazumitv`，Mac 主工作副本为后续写入入口；独立弹幕工作树只作历史保留。
UBT `/home/bw/work/KazumiTV` 同步主分支，独立构建目录留存原始测试/打包证据。

## 后续构建

使用已有 UBT Flutter/JDK/SDK 环境、原私有签名配置；先测试再构建，避免测试和
原生编译并发。为避免空闲 Gradle heap 与测试叠加耗尽 UBT 内存，构建时显式设置：

```bash
export GRADLE_OPTS='-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.jvmargs=-Xmx2048m -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process'
flutter test --concurrency=1
tool/tv/build.sh --dart-define-from-file=/private/path/defines.json
```

私有 defines 文件按需含 `KAZUMI_DANMAKU_BASE_URL`，不要提交该文件或将家庭地址
硬编码到源码。编译默认地址不会从旧 APK 或上次命令自动继承；未传参数时官方路径
仍需有效应用凭据，也可安装后通过弹幕设置配置自建服务。已交付 APK/清单属于
固定功能提交 `e87e0999`，文档提交与默认修订标签调整不代表重新验收过设备。

## 验证与边界

UBT Flutter 3.47.7 的最终完整测试 293 项通过，11 项目标回归通过。
静态分析 0 error / 0 warning，保留上游既有 info。
Mac 与飞牛链路已实测搜索→分集详情→非空 comments；芙莉莲 Bilibili 约 6600 条、
东京喰种四季 Bahamut 首集分别 1514 / 984 / 1029 / 1254 条。
复测发现 API 元数据的 Fake-IP 出站 TLS 断连，已在 AP 现有自定义规则中只为
`api.gamer.com.tw` 指定现有台湾策略并热加载，旧策略列表、其他选点和全局 DNS 保留。
数量随上游变动，不能当成固定断言。
尚待海信与极米实际安装、设置、显示与时间轴验证，不能由返回 JSON 宣称完成。
部署入口、镜像、源码、备份与回滚以 KnowledgeHub KazumiTV 弹幕专题为准。


### 2026-10-24 r5.4 ARM32 内核构建前置

自建弹幕地址与隔离鉴权保持；新的 ARM32 TV 包另需 `tool/tv/native/kernel.json` 固定 SHA 的 TLS 优化内核。参考 [native/README.md](native/README.md)，放到 `build/native/armeabi-v7a/libmpv.so` 或设置 `KAZUMI_TV_ARM32_LIBMPV`。仍使用本页的低资源 Gradle 环境，先完成原生构建再运行 Flutter 测试/APK，禁止并行叠加。临时飞牛媒体中继已撤除，正式构建不带媒体中继定义。

## 2026-10-25 17：29 客户端弹幕审计（独立分支，未发布）

范围：针对用户实拍中的重复弹幕，审计获取/替换、每秒投放、缓冲/暂停、拖动、
换集/退出、手动源选择和合并来源筛选。不是播放器全仓安全或性能审计。

- 基线：`codex/kazumitv / e3b7f2a1c7fd695e941d1af775f82aaa7b346037`。
- 修复：`codex/danmaku-client-audit-20261025 / 72dd4558b38f1aaecacc2b5ab759382a7c37e75c`。
- Mac 独立工作树：`/Users/blickwinkel/Documents/CodexProject/KazumiTV-danmaku-client-audit`。
- UBT 独立验收副本：`/home/bw/work/KazumiTV-danmaku-client-audit-20261025`。
- 状态：源码已修复并提交、离线回归通过；未合主线、未打包/安装、未连接电视或投影。
  不修改弹幕 API、缓存、凭据、解码/渲染器或运行服务；不向其他会话发送消息。

### 审计发现与处理

| 优先级 | 触发与原行为 | 本分支处理与回归 |
|---|---|---|
| P1 | 播放器连续回报同一整秒，定时器每次都读取该桶并投放；轻微回抖也能重发同一条 | 按弹幕时间轴记录已领取的秒，重复/回抖进度不重发；显式 seek、换源、偏移变更会重置，允许用户主动回看。用 1418.410/1418.990/1419.200/1418.800 等输入验证 |
| P1 | 手动取弹幕直接写共享列表，没有请求归属；旧请求晚到能混入新源/新一集，旧 finally 还能提前关闭新请求的 loading | 手动请求使用独立会话；新请求、自动新集加载、stop、init、dispose 同步使旧请求失效。关闭/返回选择面板后也不应用；实际 API 解析配合可控假 transport 验证成功/失败逆序返回 |
| P2 | 延迟投放只检查执行时的开关；快速关闭再开启，或更换弹幕数据后，旧回调可能重新通过检查 | 在开关变化、替换数据、seek、停止/退出时使旧批次失效；暂停/检测到缓冲时取消待投放批次但保留已显示画布。尚未绑定绘制控制器时的清理也可安全执行 |
| P2 | applyDanmakuLoad 调用 addDanmakus 仅追加，若重复应用同一结果会累积同一批数据 | 将加载结果视为替换快照：清空旧桶与投放游标后写入；连续两次应用同一结果仍只有一份 |
| P2 | 合并标签先命中 bilibili/bahamut 就被压成单一来源，来源关闭时会隐藏仍属于其他已开启来源的同一条 | 保留每个合并来源；其中任一来源开启即保留该条，仍只投放一次。兼容 &/＆、既有单源和未知来源；三源开关 8 种组合回归 |
| P2 | 1 秒轮询只取当前整秒，倍速或短时调度迟到会漏过中间秒 | 连续前进不超过 5 个源时间秒时补齐中间桶，各取一次；大跳转只取目标桶，避免倾倒历史。显式 seek 仍走失效/重置路径 |

手动面板的搜索/分集查询同样加入会话检查，返回上一级或关闭后，迟到响应不再改写
当前步骤。未改变弹幕文字的去重算法；不同时间的真实同文仍可出现，不以全局删除
同文掩盖客户端重复投放。

前一轮只读 API 核查：东京喰种第一季第 2 集返回中的“最后是彩蛋么。。”仅 1 条，
时间 1418.41 秒。源码和离线重放证实客户端具备上述重复投放缺陷，但缺少实拍当时
的进度/投放日志，不能把该照片的唯一根因或本修复的实机效果写成已确认。

### 验证与接续

UBT `bw-Ubuntu / bw`，Flutter 3.47.7 / Dart 3.13.5；全部验证使用既有
`/tmp/kazumitv-build.lock` 串行，运行在本任务独立目录，无需修改 SDK/主工程/设备。

- `flutter test --no-pub --concurrency=1 test/danmaku_playback_audit_test.dart test/danmaku_server_test.dart`：24 项通过，其中本次新增 16 项。
- `flutter analyze --no-pub --no-fatal-infos`：0 error / 0 warning，18 项既有 info；本次涉及的旧文件 info 仍为原有行。
- `flutter test --no-pub --concurrency=1 --reporter expanded`：334 项全部通过，耗时 52 秒。
- `python3 tool/tv/check_upstream.py`：通过；真实上游、版本、API 与四项 reviewedExtensions 哈希保持不变。
- 验证日志在 UBT 此独立副本 `build/audit/`，Mac 同工作树另有回收副本；以最终源码逐文件 SHA256 核对验证输入。

第一次测试启动缺 CMake/Ninja PATH，随后仅在本任务进程增加现有
`/home/bw/tools/android-sdk/cmake/3.22.1/bin`；测试桩最初将 clear 回调写成方法，
已纠正为 getter 后重跑。通过结果只来自修正后的最终回归，不把失败尝试算通过。

后续合入前重新比较主线和其他候选，使用普通合并保留并行开发；不得为接续 reset
其他工作树或覆盖另一会话的包。若用户安排出包，再在具体设备分别验证同一位置
重复、暂停/缓冲恢复、拖动回看、换集/换源和来源开关；当前无设备验收结论。
