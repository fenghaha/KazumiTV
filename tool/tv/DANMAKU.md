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
