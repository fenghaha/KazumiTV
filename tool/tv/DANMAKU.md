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

此修复确实需要 3 个上游文件的窄改动：danmaku API、认证客户端和设置键。
因此 `tool/tv/upstream.json` 保留真实已合入的 upstream commit、版本和 API，
另列 `reviewedExtensions` 原因和精确 SHA256；检查器只接受这批已记录内容，
其他受保护文件变化或这些文件后续变化仍失败。不能用本地 HEAD 冒充 upstream。

本分支从 r3 `37b09b35` 独立建立，未修改另一会话 r4 的工作区。
后续合并时优先保留 r4 的设置控件/焦点改动，合入本次服务与 API 适配，
协调 `upstream.json` 中的精确哈希并重跑检查、测试和固定提交构建。
本分支单独的 APK 不包含 r4 界面改动，不应标成 r4。

## 验证与边界

UBT Flutter 3.47.7 的完整测试 275 项通过；追加来源标签后的 6 项定向测试通过。
静态分析 0 error / 0 warning，保留上游既有 info。
Mac 与飞牛链路已实测搜索→分集详情→非空 comments；芙莉莲 Bilibili 约 6600 条、
东京食尸鬼第一季 Bahamut 1514 条。数量随上游变动，不能当成固定断言。
尚待海信与极米实际安装、设置、显示与时间轴验证，不能由返回 JSON 宣称完成。
部署入口、镜像、源码、备份与回滚以 KnowledgeHub KazumiTV 弹幕专题为准。
