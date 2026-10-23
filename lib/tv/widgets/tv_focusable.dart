import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single focus target for a TV control. Kept outside the upstream widgets so
/// the desktop/mobile focus and shortcut behavior does not change.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = const EdgeInsets.all(12),
    this.selected = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final String? semanticLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: enabled,
        onFocusChange: _onFocus,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 110),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: _focused
                    ? const Color(0xFF31455D)
                    : widget.selected
                    ? const Color(0xFF263A51)
                    : Colors.transparent,
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _focused
                      ? const Color(0xFFEBC889)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
