import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/tv/detail/tv_source_browser.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

/// TV presentation only. Metadata, collection and source search stay upstream.
class TvInfoPage extends StatefulWidget {
  const TvInfoPage({
    super.key,
    required this.inputBangumiItem,
    required this.infoController,
    required this.pluginsController,
  });

  final BangumiItem inputBangumiItem;
  final InfoController infoController;
  final PluginsController pluginsController;

  @override
  State<TvInfoPage> createState() => _TvInfoPageState();
}

class _TvInfoPageState extends State<TvInfoPage> {
  final _playFocus = FocusNode(debugLabel: 'TV start watching');
  bool _loading = false;
  bool _collecting = false;
  String? _metadataError;

  BangumiItem get _item => widget.infoController.bangumiItem;

  @override
  void initState() {
    super.initState();
    widget.infoController.bangumiItem = widget.inputBangumiItem;
    unawaited(_loadMetadata());
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _loading = true;
      _metadataError = null;
    });
    try {
      await widget.infoController.queryBangumiInfoByID(
        _item.id,
        type: 'attach',
      );
    } catch (_) {
      if (mounted) _metadataError = '详细介绍暂时未能加载，仍可选择播放源。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _playFocus.dispose();
    super.dispose();
  }

  Future<void> _startWatching() async {
    if (widget.pluginsController.pluginList.isEmpty) {
      await context.pushNamed('/tv/rules');
      if (mounted) setState(() {});
      return;
    }
    final advanced = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TvSourceBrowser(
          infoController: widget.infoController,
          pluginsController: widget.pluginsController,
        ),
      ),
    );
    if (!mounted) return;
    if (advanced == true) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width * .86,
            height: MediaQuery.sizeOf(context).height * .86,
            child: SourceSheet(infoController: widget.infoController),
          ),
        ),
      );
    }
    if (mounted) _playFocus.requestFocus();
  }

  Future<void> _toggleCollection() async {
    if (_collecting) return;
    setState(() => _collecting = true);
    try {
      final controller = widget.infoController.collectController;
      if (controller.getCollectType(_item) == 0) {
        await controller.addCollect(_item, type: 1);
      } else {
        await controller.deleteCollect(_item);
      }
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _item.nameCn.isEmpty ? _item.name : _item.nameCn;
    final collected =
        widget.infoController.collectController.getCollectType(_item) != 0;
    return Scaffold(
      backgroundColor: const Color(0xFF101C2C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusable(
                    semanticLabel: '返回片库',
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back_rounded),
                        SizedBox(width: 8),
                        Text('返回片库'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '番剧详情',
                    style: TextStyle(color: Color(0xFFAAB9CB), fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final posterWidth = (bounds.maxWidth * .23).clamp(
                      150.0,
                      290.0,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: NetworkImgLayer(
                            src:
                                _item.images['large'] ?? _item.images['common'],
                            width: posterWidth,
                            height: (posterWidth * 1.45).clamp(
                              160.0,
                              bounds.maxHeight,
                            ),
                          ),
                        ),
                        const SizedBox(width: 36),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFF5F1E8),
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_item.name.isNotEmpty &&
                                    _item.name != title) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _item.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFFAAB9CB),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 24,
                                  runSpacing: 8,
                                  children: [
                                    if (_item.ratingScore > 0)
                                      Text(
                                        '★ ${_item.ratingScore.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          color: Color(0xFFEBC889),
                                        ),
                                      ),
                                    if (_item.airDate.isNotEmpty)
                                      Text(
                                        _item.airDate,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          color: Color(0xFFAAB9CB),
                                        ),
                                      ),
                                    if (_item.rank > 0)
                                      Text(
                                        'Bangumi 排名 ${_item.rank}',
                                        style: const TextStyle(
                                          fontSize: 19,
                                          color: Color(0xFFAAB9CB),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    TvFocusable(
                                      autofocus: true,
                                      focusNode: _playFocus,
                                      onPressed: _startWatching,
                                      selected: true,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 18,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            widget
                                                    .pluginsController
                                                    .pluginList
                                                    .isEmpty
                                                ? '添加播放规则'
                                                : '选择播放源',
                                            style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TvFocusable(
                                      onPressed: _collecting
                                          ? null
                                          : _toggleCollection,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            collected
                                                ? Icons.bookmark_rounded
                                                : Icons.bookmark_add_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(collected ? '取消收藏' : '加入追番'),
                                        ],
                                      ),
                                    ),
                                    TvFocusable(
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => InfoPage(
                                              inputBangumiItem: _item,
                                              infoController:
                                                  widget.infoController,
                                              pluginsController:
                                                  widget.pluginsController,
                                            ),
                                          ),
                                        );
                                        if (mounted) setState(() {});
                                      },
                                      child: const Text('完整资料与评价'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                if (_loading)
                                  const LinearProgressIndicator(minHeight: 2),
                                if (_metadataError != null) ...[
                                  Text(
                                    _metadataError!,
                                    style: const TextStyle(
                                      color: Color(0xFFAAB9CB),
                                    ),
                                  ),
                                  TvFocusable(
                                    onPressed: _loadMetadata,
                                    child: const Text('重试加载介绍'),
                                  ),
                                ],
                                Text(
                                  _item.summary.isEmpty
                                      ? '暂无简介'
                                      : _item.summary,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    height: 1.65,
                                    color: Color(0xFFCBD5E2),
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '方向键选择  ·  确认进入  ·  返回回到片库',
                style: TextStyle(color: Color(0xFFAAB9CB), fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
