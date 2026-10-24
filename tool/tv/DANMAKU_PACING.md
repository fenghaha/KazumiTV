# 弹幕帧节奏追踪（2026-10-25）

## 范围和验收目标

用户已否定 Native3 原生 SurfaceView 方案，反馈“比之前卡一点点”。本轮从主线 `4be7e62b` 新建 `codex/danmaku-pacing-20261025`，不继承 SurfaceProducer、Skia 切换、原生 SurfaceView 或私有窗口监听接管。

2026-10-25 用户明确：**稳定30fps以上、实际滚动看不出明显卡顿即可**，不以60fps作为交付硬门槛。平均fps必须配合帧间隔p95/p99、超过50ms的长帧和本人观感判断；片源本身约24fps不作为弹幕帧率。

保留已修复的 ARM32 TLS 内核、原 Emby 302 → CDN、现有弹幕服务、内容/数量/字号/描边及播放内设置。主线 `codex/kazumitv` 暂不合并本轮追踪改动，先实测再决定最小优化。

## 并行会话和构建边界

“视频网速”会话先占用极米做网络测试。用户已授权发消息协调，只有它明确交接、停止测速流量后，本会话才安装或操作设备。不得同时测网络与绘制，或把另一会话的网络测试扰动当作弹幕数据。

- Mac：`/Users/blickwinkel/Documents/CodexProject/KazumiTV-danmaku-pacing`
- UBT：`/home/bw/work/KazumiTV-danmaku-pacing`
- 不复用 canonical 构建目录，不改另一会话的测速文件，不关临时ADB调试通道。
- 构建/测试顺序执行，Gradle单worker/2GiB/in-process Kotlin，签名文件留在既有私有路径。

## 可测量基线

独立提取打开信息面板/控件前冻结采样的修正； profile 模式另提供只读 VM service 扩展 `ext.kazumi.tv.frames`，输出有界帧时间戳/UI/绘制耗时，不暴露媒体URL、设置或播放命令，release不注册扩展。

`android/tv.gradle` 让 profile 构建也使用同一外部签名和校验过的 ARM32 优化内核。否则 profile 会退回未优化的上游库，重现已修复的读取瓶颈，无法作为绘制对照。必须核 APK 内核 SHA 与证书后才安装；保留数据，不卸载清空。

用与 release 相同的私有弹幕默认地址、`KAZUMI_BUILD_TV=1` 和既有签名环境构建：

```sh
flutter build apk --profile --no-pub --split-per-abi \
  --target-platform android-arm --flavor livingroom \
  --dart-define=KAZUMI_TV=true \
  --dart-define=KAZUMI_TV_REVISION=r5.4-pacing-base
```

以上命令省略私有地址和签名环境具体值；不能据此遗漏真实构建配置。目标设备/包信息必须另记。

## 采样流程

1. 网络会话交接后，记录设备负载/温控/后台编译是否空闲，覆盖安装profile基线。
2. 固定《东京喰种》第一季首集12:00附近，同一批弹幕和样式，关闭控件、信息HUD，确认未自动跳集。
3. ADB仅转发VM service到Mac loopback；带认证的URI放本机0600临时文件，不进Git、文档或聊天。
4. 运行 `python3 tool/tv/profile_playback.py --uri-file <私有URI文件> --output build/verification/pacing/baseline --seconds 30`。脚本只重置诊断计数/采集Timeline和CPU样本，不操作播放器，不下载媒体，不改缓存策略。
5. 比较 UI、raster、系统合成。`timeline_durations` 是可嵌套的事件累计耗时，不可直接相加当作CPU使用率。profile有额外追踪开销，最终性能仍在release包复验。
6. 先有热点证据，再改对应层；预读60秒仅为独立候选，当前没有实施，避免与“视频网速”会话变量冲突。

现有 `canvas_danmaku 0.3.3` 已缓存每条文字位图。新增弹幕时会同步排字/创建位图，绘制时仅在位图缺失后重建，不应再描述为“每帧重新生成文字”。只有追踪证明该路径主导长帧后才优化。

## 验证状态

- 追踪基线：312项Flutter测试、3项原生构建脚本测试通过；静态检查0 error/0 warning、18条既有info；上游契约检查通过。
- 当前仅准备基线与工具，尚无本轮实机结果。测试通过不代表弹幕性能修复。
- 实际安装、源码SHA、APK/内核哈希、严格同输入对照和用户验收在本节后续追加，不复用 Native3 的316项或 Native4 的317项测试数。

回退保留原Native3包与旧实验分支作为证据，不把它当稳定交付；最终回退应使用包含TLS、播放设置和字号修复的同签名主线release构建。
