import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/tv_page_scaffold.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

/// A television welcome screen. It only records consent; package updates remain
/// outside this flow so an upstream phone APK cannot replace the TV build.
class TvWelcomePage extends StatefulWidget {
  const TvWelcomePage({super.key, required this.pluginsController});

  final PluginsController pluginsController;

  @override
  State<TvWelcomePage> createState() => _TvWelcomePageState();
}

class _TvWelcomePageState extends State<TvWelcomePage> {
  final _scrollController = ScrollController();
  final _readingFocus = FocusNode(debugLabel: 'TV welcome disclaimer');
  String? _statements;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatements());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _readingFocus.dispose();
    super.dispose();
  }

  Future<void> _loadStatements() async {
    setState(() {
      _loading = true;
      _failed = false;
      _statements = null;
    });
    try {
      final text = await rootBundle.loadString(
        'assets/statements/statements.txt',
      );
      if (text.trim().isEmpty) throw const FormatException('Empty disclaimer');
      if (!mounted) return;
      setState(() {
        _statements = text;
        _loading = false;
      });
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'TV onboarding: failed to load statements',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _chooseRules() async {
    if (_saving) return;
    await context.pushNamed('/tv/rules');
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    if (_saving || _loading || _failed || _statements == null) return;
    setState(() => _saving = true);
    try {
      // A personal build does not inherit the upstream mirror's app secrets.
      // Use the public API on first setup; preserve explicit/imported choices.
      if (GStorage.getSetting(SettingsKeys.bangumiAcceleration).isEmpty &&
          ((bangumiMirrorCredentials['id'] ?? '').isEmpty ||
              (bangumiMirrorCredentials['value'] ?? '').isEmpty)) {
        await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      }
      await GStorage.putSetting(SettingsKeys.onboardingCompleted, true);
      if (mounted) context.navigate('/tab/popular');
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'TV onboarding: failed to save completion',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能保存欢迎设置，请重试')));
    }
  }

  KeyEventResult _readWithRemote(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_scrollController.hasClients) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.pageDown => 1.0,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp => -1.0,
      _ => 0.0,
    };
    if (direction == 0) return KeyEventResult.ignored;
    final position = _scrollController.position;
    final step =
        (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp)
        ? position.viewportDimension * .8
        : 100.0;
    final target = (position.pixels + direction * step)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    // At either edge, let normal focus traversal reach the actions below.
    if ((target - position.pixels).abs() < 1) return KeyEventResult.ignored;
    _scrollController.jumpTo(target);
    return KeyEventResult.handled;
  }

  Widget _guide({required bool compact}) {
    final count = widget.pluginsController.pluginList.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          const Icon(Icons.tv_rounded, color: TvTheme.focus, size: 44),
          const SizedBox(height: 20),
          const Text(
            '拿起遥控器，\n准备开始。',
            style: TextStyle(fontSize: 30, height: 1.3),
          ),
          const SizedBox(height: 28),
        ],
        const Text(
          '方向键移动 · 确认键选择 · 返回键返回',
          style: TextStyle(color: TvTheme.ink, fontSize: 17, height: 1.6),
        ),
        const SizedBox(height: 10),
        const Text(
          '输入框按确认键打开输入法；也可用手机扫码输入。',
          style: TextStyle(color: TvTheme.muted, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 16),
        Text(
          count == 0
              ? '没有预装播放源。可以先选择规则，或进入后在设置中添加。'
              : '已安装 $count 条规则。可以继续管理，也可以直接开始。',
          style: const TextStyle(
            color: TvTheme.muted,
            fontSize: 16,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _disclaimer() => Focus(
    focusNode: _readingFocus,
    autofocus: true,
    onKeyEvent: _readWithRemote,
    onFocusChange: (focused) {
      if (mounted) setState(() => _reading = focused);
    },
    child: GestureDetector(
      onTap: _readingFocus.requestFocus,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TvTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _reading ? TvTheme.focus : Colors.transparent,
            width: 3,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '使用说明与免责声明',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '上下键阅读全文，读到底后按下键选择按钮',
              style: TextStyle(color: TvTheme.muted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _failed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('免责声明加载失败，请重试'),
                          const SizedBox(height: 16),
                          TvFocusable(
                            onPressed: _loadStatements,
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          _statements!,
                          style: const TextStyle(fontSize: 18, height: 1.65),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _actions() => Wrap(
    alignment: WrapAlignment.end,
    spacing: 18,
    runSpacing: 8,
    children: [
      TvFocusable(
        onPressed: _saving ? null : _chooseRules,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined),
            SizedBox(width: 10),
            Text('选择播放规则', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
      TvFocusable(
        selected: true,
        onPressed: _saving || _loading || _failed ? null : _finish,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          _saving ? '正在保存…' : '同意并进入 KazumiTV',
          style: const TextStyle(fontSize: 20, color: TvTheme.focus),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: TvPageScaffold(
      title: '欢迎使用 KazumiTV',
      subtitle: '为电视与投影仪准备的观看界面',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final compact = constraints.maxHeight < 520;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: compact ? 240 : 300,
                            child: SingleChildScrollView(
                              child: _guide(compact: compact),
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: _disclaimer()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _guide(compact: true),
                          const SizedBox(height: 16),
                          Expanded(child: _disclaimer()),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              _actions(),
            ],
          );
        },
      ),
    ),
  );
}
