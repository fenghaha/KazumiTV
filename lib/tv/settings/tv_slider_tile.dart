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
    this.parentHandlesBack = false,
  });
  final bool enabled;
  /// The player owns remote/system Back and calls [TvSliderTileState.blur].
  final bool parentHandlesBack;
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
  // Back removes the slider highlight, but keeps a spatial origin for the next
  // Up/Down. Unfocusing into the route scope would lose that origin.
  final _navigationFocus = FocusNode(
    debugLabel: 'TV slider navigation anchor',
    skipTraversal: true,
  );
  bool _focused = false;
  bool get isFocused => _focused;
  bool _disposing = false;
  TvSettingsNavigationController? _navigation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = TvSettingsEditorScope.of(context);
    if (identical(navigation, _navigation)) return;
    _navigation?.clearEditor(this);
    _navigation = navigation;
    if (_focused) _navigation?.registerEditor(this, blur);
  }

  void _onFocusChange(bool focused) {
    if (!mounted || _disposing || focused == _focused) return;
    setState(() => _focused = focused);
    if (focused) {
      _navigation?.registerEditor(this, blur);
    } else {
      _navigation?.clearEditor(this);
    }
  }

  void blur() {
    if (!_focused) return;
    _onFocusChange(false);
    _navigationFocus.requestFocus();
  }

  @override
  void dispose() {
    _disposing = true;
    _navigation?.clearEditor(this);
    _focus.dispose();
    _navigationFocus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (node.hasPrimaryFocus &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      // The anchor must never enter directional history: reversing direction
      // should focus the slider again, rather than revisit its invisible anchor.
      final policy = FocusTraversalGroup.maybeOf(context);
      final scope = node.nearestScope;
      if (scope != null) policy?.invalidateScopeData(scope);
      node.focusInDirection(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      if (scope != null) policy?.invalidateScopeData(scope);
      return KeyEventResult.handled;
    }
    if (!_focused) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) blur();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (!widget.enabled) return KeyEventResult.handled;
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
    // Settings/player routes consume Back themselves. Only standalone sheets
    // need this PopScope, otherwise one platform pop could also close a menu.
    canPop: widget.parentHandlesBack || _navigation != null || !_focused,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !widget.parentHandlesBack && _navigation == null) blur();
    },
    child: Focus(
      focusNode: _navigationFocus,
      onKeyEvent: _key,
      child: TvFocusable(
        focusNode: _focus,
        focusableWhenDisabled: true,
        onPressed: widget.enabled ? _focus.requestFocus : null,
        onFocusChange: _onFocusChange,
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
                onChangeStart: widget.enabled
                    ? (_) => _focus.requestFocus()
                    : null,
                onChanged: widget.enabled ? widget.onChanged : null,
              ),
            ),
            Text(
              _focused ? '左右调节 · 上下换项 · 返回取消焦点' : '上下换项 · 获焦后左右调节',
              style: TextStyle(
                color: _focused ? TvTheme.focus : TvTheme.muted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
