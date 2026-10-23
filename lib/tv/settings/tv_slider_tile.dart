import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/settings/tv_settings_navigation.dart';

class TvSliderTile extends StatefulWidget {
  const TvSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.leading,
    this.description,
    this.enabled = true,
  });
  final bool enabled;
  final Widget title;
  final Widget? description;
  final IconData? leading;
  final double value, min, max;
  final String valueLabel;
  final int? divisions;
  final ValueChanged<double> onChanged;
  @override
  State<TvSliderTile> createState() => TvSliderTileState();
}

class TvSliderTileState extends State<TvSliderTile> {
  final _focus = FocusNode(debugLabel: 'TV adjustable setting');
  bool _editing = false;
  bool get isEditing => _editing;
  void finishEditing() => _end();
  bool _disposing = false;
  TvSettingsNavigationController? _navigation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigation = TvSettingsEditorScope.of(context);
  }

  void _begin() {
    if (_editing) return;
    setState(() => _editing = true);
    _navigation?.registerEditor(this, _end);
  }

  void _end() {
    _navigation?.clearEditor(this);
    if (mounted && !_disposing && _editing) setState(() => _editing = false);
  }

  @override
  void dispose() {
    _disposing = true;
    _navigation?.clearEditor(this);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!_editing) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _end();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _end();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final step = (widget.max - widget.min) / (widget.divisions ?? 100);
      final next =
          (widget.value + (key == LogicalKeyboardKey.arrowRight ? step : -step))
              .clamp(widget.min, widget.max)
              .toDouble();
      if (next != widget.value) widget.onChanged(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_editing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _editing) _end();
    },
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: TvFocusable(
        focusNode: _focus,
        focusableWhenDisabled: true,
        onPressed: widget.enabled ? () => _editing ? _end() : _begin() : null,
        onFocusChange: (focused) {
          if (!focused) _end();
        },
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.leading != null) ...[
                  Icon(widget.leading, color: TvTheme.muted),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 20),
                    child: widget.title,
                  ),
                ),
                Text(
                  widget.valueLabel,
                  style: const TextStyle(color: TvTheme.focus, fontSize: 20),
                ),
              ],
            ),
            if (widget.description != null) widget.description!,
            ExcludeFocus(
              child: Slider(
                value: widget.value,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                onChangeStart: (_) {
                  _focus.requestFocus();
                  _begin();
                },
                onChangeEnd: (_) => _end(),
                onChanged: widget.enabled ? widget.onChanged : null,
              ),
            ),
            Text(
              _editing ? '左右调节 · 确认或返回结束 · 上下换项' : '按确认调节 · 上下换项',
              style: TextStyle(
                color: _editing ? TvTheme.focus : TvTheme.muted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
