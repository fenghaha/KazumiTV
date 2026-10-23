import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/tv_page_scaffold.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

/// Uses the upstream catalog, importer and persistence without another rule
/// format or a second installed-rule store.
class TvRulesPage extends StatefulWidget {
  const TvRulesPage({super.key, required this.controller});

  final PluginsController controller;

  @override
  State<TvRulesPage> createState() => _TvRulesPageState();
}

class _TvRulesPageState extends State<TvRulesPage> {
  bool _shop = false;
  bool _busy = false;
  bool _loadingCatalog = false;
  String? _catalogError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
  }

  Future<void> _loadCatalog({bool refresh = false}) async {
    if (_loadingCatalog) return;
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      if (refresh) {
        await widget.controller.refreshPluginCatalog();
      } else {
        await widget.controller.ensurePluginCatalog();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = '规则商店暂时无法连接，已安装规则仍可使用。');
      }
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = '正在处理…';
    });
    try {
      final result = await action();
      if (mounted) setState(() => _notice = result);
    } catch (_) {
      if (mounted) setState(() => _notice = '操作未完成，请重试。已保存的规则会保留。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(String name, {required bool installing}) => _run(
    () async {
      // This controller checks requiresNewerClient and payload identity before
      // saving, for both a new installation and an update.
      final result = await widget.controller.tryUpdatePluginByName(name);
      return switch (result) {
        PluginUpdateResult.updated => '${installing ? '已安装' : '已更新'}：$name',
        PluginUpdateResult.requiresNewerClient =>
          '$name 需要更高版本客户端；当前规则 API 为 ${ApiEndpoints.apiLevel}，未安装此版本。',
        PluginUpdateResult.notNewer => '$name 已是当前版本，未覆盖本地规则。',
        PluginUpdateResult.failed => '$name 下载失败，请稍后重试。',
      };
    },
  );

  Future<void> _updateAll() => _run(() async {
    final result = await widget.controller.tryUpdateAllPlugin();
    if (result.hasNoCandidates) return '没有可更新的规则。';
    return '更新 ${result.updated} 条 · 不兼容 ${result.requiresNewerClient} 条'
        ' · 失败 ${result.failed} 条 · 跳过 ${result.notNewer} 条';
  });

  Future<void> _remove(Plugin plugin) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 ${plugin.name}？'),
        content: const Text('此播放源将从已安装规则中移除。之后可以重新从商店安装或导入。'),
        actions: [
          TvFocusable(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          TvFocusable(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(() async {
      await widget.controller.removePlugin(plugin);
      return '已移除：${plugin.name}';
    });
  }

  Future<void> _import() async {
    if (_busy) return;
    final imported = await showDialog<int>(
      context: context,
      builder: (_) => _RuleImportDialog(controller: widget.controller),
    );
    if (mounted && imported != null) {
      setState(() {
        _shop = false;
        _notice = '已导入 $imported 条规则。';
      });
    }
  }

  Widget _button(
    String text,
    VoidCallback? onPressed, {
    bool selected = false,
    bool autofocus = false,
  }) => TvFocusable(
    // Busy rule actions must not remove the current D-pad focus target. Keep
    // navigation independent from activation; null callbacks reject repeats.
    focusableWhenDisabled: true,
    autofocus: autofocus,
    selected: selected,
    onPressed: onPressed,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 18,
        color: onPressed == null ? TvTheme.muted : TvTheme.ink,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => TvPageScaffold(
    title: '规则与播放源',
    subtitle:
        '不预装播放源 · 支持上游规则 JSON 与 kazumi:// 链接 · 规则 API ${ApiEndpoints.apiLevel}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _button(
              '已安装',
              () => setState(() => _shop = false),
              selected: !_shop,
              autofocus: true,
            ),
            _button(
              '规则商店',
              () => setState(() => _shop = true),
              selected: _shop,
            ),
            _button('导入规则', _busy ? null : _import),
            _button(
              '刷新商店',
              _loadingCatalog || _busy
                  ? null
                  : () => _loadCatalog(refresh: true),
            ),
            _button('更新已安装规则', _busy || _loadingCatalog ? null : _updateAll),
          ],
        ),
        if (_loadingCatalog || _busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_catalogError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _catalogError!,
              style: const TextStyle(color: TvTheme.focus),
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _notice!,
                style: const TextStyle(color: TvTheme.focus),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: Observer(
            builder: (_) {
              final installed = widget.controller.pluginList.toList();
              final catalog = widget.controller.pluginHTTPList.toList();
              if (_shop) {
                if (catalog.isEmpty) {
                  return _empty(
                    _loadingCatalog
                        ? '正在获取规则商店…'
                        : _catalogError != null
                        ? '商店未加载，可使用上方“刷新商店”重试。'
                        : '商店暂无规则，也可以自行导入规则。',
                  );
                }
                return ListView.builder(
                  key: const PageStorageKey('tv-rule-catalog'),
                  itemCount: catalog.length,
                  itemBuilder: (_, index) => _catalogRow(catalog[index]),
                );
              }
              if (installed.isEmpty) {
                return _empty('还没有播放源\n选择“规则商店”安装，或使用“导入规则”添加自己的来源。');
              }
              return ListView.builder(
                key: const PageStorageKey('tv-installed-rules'),
                itemCount: installed.length,
                itemBuilder: (_, index) => _installedRow(installed[index]),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _empty(String message) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, height: 1.7, color: TvTheme.muted),
    ),
  );

  Widget _row(String name, String details, List<Widget> actions) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: TvTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(
              Icons.extension_outlined,
              color: TvTheme.focus,
              size: 30,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 23),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TvTheme.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ...actions,
          ],
        ),
      ),
    ),
  );

  Widget _installedRow(Plugin plugin) {
    final status = widget.controller.pluginUpdateStatus(plugin);
    final api = int.tryParse(plugin.api);
    final compatibility = api == null
        ? ' · API 格式无效，请重新导入'
        : api > ApiEndpoints.apiLevel
        ? ' · 需要更高版本客户端'
        : '';
    final label = switch (status) {
      PluginUpdateAvailability.unknown => '检查更新',
      PluginUpdateAvailability.notInCatalog => '商店未收录',
      PluginUpdateAvailability.latest => '已是最新',
      PluginUpdateAvailability.updatable => '更新',
    };
    final canUpdate =
        status == PluginUpdateAvailability.unknown ||
        status == PluginUpdateAvailability.updatable;
    return _row(
      plugin.name,
      '版本 ${plugin.version} · API ${plugin.api}$compatibility',
      [
        _button(
          label,
          _busy || !canUpdate
              ? null
              : () => _download(plugin.name, installing: false),
        ),
        _button('移除', _busy ? null : () => _remove(plugin)),
      ],
    );
  }

  Widget _catalogRow(PluginHTTPItem item) {
    final status = widget.controller.pluginStatus(item);
    final label = switch (status) {
      PluginCatalogItemStatus.install => '安装',
      PluginCatalogItemStatus.installed => '已安装',
      PluginCatalogItemStatus.update => '更新',
    };
    return _row(item.name, '版本 ${item.version} · ${item.author}', [
      // Keep installed catalog entries focusable so a full viewport of already
      // installed rules cannot block D-pad traversal to the next page of rows.
      _button(
        label,
        _busy
            ? null
            : status == PluginCatalogItemStatus.installed
            ? () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(item.name),
                  content: Text(
                    '已安装此规则，商店版本为 ${item.version}。\n'
                    '可以在“已安装”中管理和移除。',
                  ),
                  actions: [
                    TvFocusable(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              )
            : () => _download(
                item.name,
                installing: status == PluginCatalogItemStatus.install,
              ),
      ),
    ]);
  }
}

class _RuleImportDialog extends StatefulWidget {
  const _RuleImportDialog({required this.controller});
  final PluginsController controller;

  @override
  State<_RuleImportDialog> createState() => _RuleImportDialogState();
}

class _RuleImportDialogState extends State<_RuleImportDialog> {
  final _text = TextEditingController();
  PluginImportParseResult? _preview;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _inspect() {
    if (_saving) return;
    setState(() {
      _preview = PluginImportParser.parse(_text.text);
      _error = null;
    });
  }

  Future<void> _save() async {
    final preview = _preview;
    if (_saving || preview == null || preview.plugins.isEmpty) return;
    setState(() => _saving = true);
    try {
      // Parser excludes newer API levels. Do not send rejected entries through
      // updatePlugins, whose job is persistence, not compatibility validation.
      await widget.controller.updatePlugins(preview.plugins);
      if (mounted) Navigator.of(context).pop(preview.plugins.length);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。原有规则已保留。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final existing = widget.controller.pluginList
        .map((p) => pluginNameKey(p.name))
        .toSet();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('导入播放源规则'),
        content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '输入规则 JSON 或 kazumi:// 链接。可以用手机扫码粘贴多条规则。',
                  style: TextStyle(color: TvTheme.muted),
                ),
                const SizedBox(height: 16),
                TvTextInput(
                  controller: _text,
                  label: '规则内容',
                  hintText: 'JSON / kazumi://',
                  multiline: true,
                  maxLength: 131072,
                  autofocus: true,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {
                    _preview = null;
                    _error = null;
                  }),
                  onSubmitted: (_) => _inspect(),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '可导入 ${preview.plugins.length} 条 · 不可导入 ${preview.failureCount} 条',
                    style: const TextStyle(color: TvTheme.focus, fontSize: 20),
                  ),
                  if (preview.duplicateCount > 0)
                    Text('同一批内有 ${preview.duplicateCount} 条重名规则，使用最后一条。'),
                  for (final plugin in preview.plugins)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${plugin.name}  ·  ${plugin.version}'
                        '${existing.contains(pluginNameKey(plugin.name)) ? '  ·  将替换已有规则' : ''}',
                      ),
                    ),
                  for (final failure in preview.failures)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        failure,
                        style: const TextStyle(color: TvTheme.muted),
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: TvTheme.focus)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TvFocusable(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TvFocusable(
            onPressed: _saving ? null : _inspect,
            child: const Text('检查内容'),
          ),
          TvFocusable(
            onPressed: _saving || preview == null || preview.plugins.isEmpty
                ? null
                : _save,
            child: Text(
              _saving ? '保存中…' : '确认导入 ${preview?.plugins.length ?? 0} 条',
            ),
          ),
        ],
      ),
    );
  }
}
