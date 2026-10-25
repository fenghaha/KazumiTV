# 极米离线准备（2026-10-25）

## 用户边界

用户要完整看一集体验已接受最低要求的r5.5，本轮只做离线可完成工作。没有ADB读取/遥控、安装、播放参数调整、压力测速或服务改动；构建使用独立UBT工作树，不占用设备。观察窗口何时结束以用户后续消息为准，不能按经过26分钟自动接管。

本轮还要求性能调优先限极米，海信配置未知，留待以后实测。新源码和已装包分开：已装r5.5源53cb1f27不变；后续源码/待验证包有设备配置档，不把编译和单测当成实机验收。

## 设备配置档

| 构建配置 | 60秒预读 | 本轮处置 |
|---|---|---|
| 默认`generic` | 不启用该覆盖，沿用既有播放器行为 | 通用/海信暂用此基线；没有新增海信调优 |
| 显式`xgimi-z9x` | Android TV且已知RAM≤2GiB时启用 | 仅为已验证极米准备专用ARM32包 |
| 未定义的`hisense`等名称 | 构建脚本在调用Flutter前拒绝；策略也不会套用Z9X | 以后实测再建立新配置，不能仅按RAM猜测 |

这是构建目标白名单，不是通过MAC/序列号/IP识别设备。传设备档时保持原签名和私有弹幕defines；环境变量不自动从旧APK继承。原ARM32 TLS构建优化是独立、已有验证的编译修复，不因本次收紧设备调优范围而撤销。

```sh
KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x tool/tv/build.sh --target-platform android-arm
```

脚本默认revision为`r5.5.1-xgimi-z9x`或`r5.5.1-generic`。发布字段仍2.4.1/API9，不改规则兼容契约。`test_device_profiles.py`用临时假Flutter检查真实脚本argv和未知设备失败路径，不访问设备。

## 已有数据的离线复核

对r5.5准备阶段保存的`controlled-b2-cold/frames.json`复核：30.034秒/1261帧，平均41.95fps；71个超过50ms的帧间隔。20帧UI wall time超过50ms，其中7帧超过100ms；8帧绘制wall time超过50ms。36个长间隔邻接UI耗时>33.3ms的帧，13个邻接绘制耗时>33.3ms的帧；计数可重叠，不能相加当作已找到全部原因。

这些是旧profile包的数据，不是当前release的新采样。UI wall time可包含排队、GC、原生调用或资源等待；邻接关系也不能证明是排字或文字位图生成。优先查偶发UI长耗时，有证据后再动缓存/绘制算法。

静态代码复核：`canvas_danmaku 0.3.3`的滚动/静态/高级层已有各自的RepaintBoundary，滚动/高级层仍通过ValueListenableBuilder随ticker刷新。不能把“没有位图缓存/没有隔离”当成现状；若后续改为paint-only刷新，应按极米配置做独立对照，不能离线声称已有收益。

```sh
python3 tool/tv/analyze_frame_stalls.py build/verification/pacing/controlled-b2-cold/frames.json \
  --output build/verification/offline-20261025/b2-stall-analysis.json
```

旧原始数据不改写，新报告独立保存。平均fps较高不抵消偶发100ms级停顿；本轮没有声称进一步改善。

## 下一次可用的入场耗时标记

`TvDanmakuTrace`仅在**profile运行模式+显式极米配置档+TV模式+显式`KAZUMI_TV_TRACE_DANMAKU=true`**时记录`TV.Danmaku.add`，围住库的同步add入口（包含入场判断、排字与首次位图准备）。现有库已经缓存位图，不能描述成每帧重新生成。

事件只带类型和文本长度，不记录弹幕原文、媒体地址或账号。正常release不启用；通用/海信配置不启用。未启用时原对象仅转发一次，异常保持原样，不重试、不改弹幕数量、样式或时间轴。profile帧扩展另增加build/raster起止时间，方便以后做时间关联。

下次构建profile需保留既有KAZUMI_BUILD_TV、私有签名和私有弹幕defines，并显式传：

```text
--profile --flavor livingroom --target-platform android-arm --split-per-abi
--dart-define=KAZUMI_TV=true
--dart-define=KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x
--dart-define=KAZUMI_TV_TRACE_DANMAKU=true
--dart-define=KAZUMI_TV_REVISION=r5.5.1-xgimi-trace
```

用户结束观察并允许接管后，再安装追踪包、固定同片段并用`profile_playback.py --timeline`采集。输出`danmaku_admission`单独给出次数/p95/最大值/超过33ms次数；没有事件时标记`not_observed`，不能写成0ms。若入场标记短但UI仍长，再查每秒轮询、GC或图形同步，不先大改视频输出。

原生SurfaceView、SurfaceProducer/Skia切换和字体/密度削减均未带回。当前只完成范围隔离、测量准备和离线检查，真实收益待后续实机对照。

## 离线检查和待验证包

实际功能构建源码`0425570b4450332e6369038afd31608b1bcd99d8`；后续文档不代表再改运行逻辑。318项Flutter全量测试通过，0error/0warning、18条既有info；4项构建配置argv、5项帧数据/事件汇总和3项既有原生构建脚本测试均通过。

仅准备极米ARM32，两包在UBT独立工作树`build/candidates/xgimi-offline-20261025/`，没有安装，也没有构建/安装新的海信包：

| 包 | SHA256 | 状态 |
|---|---|---|
| `KazumiTV-r5.5.1-xgimi-z9x-release.apk` | `12b8f70323c453a044bceb360f22301cfaa12a89366b1f1e433a42daae9d0b72` | 待验证候选；入场追踪事件未进入release |
| `KazumiTV-r5.5.1-xgimi-z9x-trace.apk` | `49d6b2f7a366ed1ed38763162612cf76e28f874865f490051baf8f426cd8eaa0` | profile测量包；事件已编入，不代表性能优化 |

签名与既有r5.5相同，16KiB对齐检查通过，两个包的ARM32优化内核均保持既有固定SHA。为减少观看期间的数据传输，仅将小型清单/分析报告回传Mac，APK留构建机；设备上仍保留r5.5。整集体验结果等用户反馈，经过一集时长不等于授权自动接管。

UBT曾对两份新测试做Dart格式化，已与正式提交逐字节核对一致。只包含这两文件的`offline-format-before-tested-commit`备份stash保留，不是待合入功能，不要直接套用到后续工作。


## 2026-10-25 海信起播缓冲的独立范围

新增明确的`hisense-mt9655`构建目标，仅网络播放使用mpv原生10秒起播/恢复缓冲门槛；它不调用usesXgimiTuning、不启用Z9X的60秒预读限制。generic与xgimi-z9x的行为保持，裸`hisense`仍作为未知目标拒绝。默认TV修订标签跟随本次r5.6.1，ABI仍由调用方显式选择，海信交付使用android-arm64。用户已确认海信r5.6弹幕较流畅，本次不继续改绘制；极米按用户要求关机，不能将离线视为故障而自动接管。
