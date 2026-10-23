import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

/// Reuses upstream search/chapter services; only the presentation differs.
class TvSourceBrowser extends StatefulWidget {
  const TvSourceBrowser({
    super.key,
    required this.infoController,
    required this.pluginsController,
  });
  final InfoController infoController;
  final PluginsController pluginsController;

  @override
  State<TvSourceBrowser> createState() => _TvSourceBrowserState();
}

class _TvSourceBrowserState extends State<TvSourceBrowser> {
  late final _search = PluginSearchService(
    infoController: widget.infoController,
    pluginsController: widget.pluginsController,
  );
  late final _keyword = TextEditingController(
    text: widget.infoController.bangumiItem.nameCn.isEmpty
        ? widget.infoController.bangumiItem.name
        : widget.infoController.bangumiItem.nameCn,
  );
  final _resultFocusNodes = <String, FocusNode>{};
  RuleCancelToken? _chapterCancel;
  String? _busySource;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search.queryAllSource(_keyword.text));
  }

  @override
  void dispose() {
    _generation++;
    _chapterCancel?.cancel();
    _search.cancel();
    _keyword.dispose();
    for (final focus in _resultFocusNodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _play(Plugin plugin, SearchItem item) async {
    if (_busySource != null) return;
    final generation = ++_generation;
    final token = _chapterCancel = RuleCancelToken();
    setState(() {
      _busySource = plugin.name;
      _error = null;
    });
    try {
      final roads = await plugin.queryChapterRoads(
        item.src,
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      if (roads.isEmpty) {
        setState(() => _error = '这个结果没有可播放剧集，请换一个结果或重试。');
        return;
      }
      await context.pushNamed(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: widget.infoController.bangumiItem,
          plugin: plugin,
          title: item.name,
          src: item.src,
          roads: roads,
        ),
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '未能取得播放列表，请重试或换一个源。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busySource = null);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.isCurrent != false) {
            _resultFocusNodes['${plugin.name}:${item.src}']?.requestFocus();
          }
        });
      }
    }
  }

  void _cancelChapter() {
    _generation++;
    _chapterCancel?.cancel();
    setState(() => _busySource = null);
  }

  void _searchAgain(String value) {
    if (value.trim().isEmpty || _busySource != null) return;
    unawaited(_search.queryAllSource(value.trim()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101C2C),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TvFocusable(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  semanticLabel: '返回详情',
                  child: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 20),
                const Text(
                  '选择播放源',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TvFocusable(
                  onPressed: _busySource == null
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('网站验证与高级检索'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TvTextInput(
                    controller: _keyword,
                    label: '检索名称',
                    hintText: '输入番剧名称或别名',
                    onSubmitted: _searchAgain,
                    enabled: _busySource == null,
                  ),
                ),
                const SizedBox(width: 12),
                TvFocusable(
                  onPressed: _busySource == null
                      ? () => _searchAgain(_keyword.text)
                      : null,
                  child: const Text('重新搜索'),
                ),
              ],
            ),
            if (_busySource != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('正在读取 $_busySource 的剧集列表…')),
                    TvFocusable(
                      onPressed: _cancelChapter,
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFEBC889)),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Observer(
                builder: (_) {
                  final plugins = widget.pluginsController.pluginList.toList();
                  final statuses = Map<String, PluginSearchStatus>.of(
                    widget.infoController.pluginSearchStatus,
                  );
                  final responses = widget
                      .infoController
                      .pluginSearchResponseList
                      .toList();
                  final results = <String, List<SearchItem>>{};
                  for (final response in responses) {
                    results
                        .putIfAbsent(response.pluginName, () => [])
                        .addAll(response.data);
                  }
                  return ListView.builder(
                    itemCount: plugins.length,
                    itemBuilder: (context, index) {
                      final plugin = plugins[index];
                      final status =
                          statuses[plugin.name] ?? PluginSearchStatus.pending;
                      final items = results[plugin.name] ?? [];
                      final message = switch (status) {
                        PluginSearchStatus.pending => '正在搜索…',
                        PluginSearchStatus.captcha => '网站要求验证，请打开右上角的网站验证。',
                        PluginSearchStatus.error => '搜索失败，可以重试或换一个源。',
                        _ => '没有匹配结果，可以修改检索名称。',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  plugin.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEBC889),
                                  ),
                                ),
                                const Spacer(),
                                if (status != PluginSearchStatus.pending)
                                  TvFocusable(
                                    onPressed: _busySource == null
                                        ? () => _search.querySource(
                                            _keyword.text.trim(),
                                            plugin.name,
                                          )
                                        : null,
                                    child: const Text('重试此源'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (items.isEmpty)
                              Text(
                                message,
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFFAAB9CB),
                                ),
                              ),
                            for (final item in items)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: TvFocusable(
                                  focusNode: _resultFocusNodes.putIfAbsent(
                                    '${plugin.name}:${item.src}',
                                    () => FocusNode(
                                      debugLabel: 'TV source result',
                                    ),
                                  ),
                                  onPressed: _busySource == null
                                      ? () => _play(plugin, item)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.play_circle_outline_rounded,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(fontSize: 21),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
