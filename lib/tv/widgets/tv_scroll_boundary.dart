import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A pane owns vertical navigation. Revealing its first control also reveals
/// the non-focusable heading/intro preceding it, rather than just a button.
class TvScrollBoundary extends StatefulWidget {
  const TvScrollBoundary({super.key, required this.child, this.onLeft});
  final Widget child;
  final VoidCallback? onLeft;

  static bool reveal(BuildContext context) {
    final owner = context.findAncestorStateOfType<TvScrollBoundaryState>();
    if (owner == null) return false;
    owner._scheduleReveal(context);
    return true;
  }

  @override
  State<TvScrollBoundary> createState() => TvScrollBoundaryState();
}

class TvScrollBoundaryState extends State<TvScrollBoundary> {
  final _scope = FocusScopeNode(debugLabel: 'TV content pane');
  int _revealGeneration = 0;

  void focusContent() {
    final previous = _scope.focusedChild;
    if (previous != null &&
        previous is! FocusScopeNode &&
        previous.context?.mounted == true &&
        previous.canRequestFocus) {
      previous.requestFocus();
      _scheduleReveal(previous.context!);
      return;
    }
    final nodes =
        _scope.traversalDescendants
            .where(
              (node) =>
                  node is! FocusScopeNode &&
                  node.context?.mounted == true &&
                  !node.rect.isEmpty,
            )
            .toList()
          ..sort((a, b) {
            final row = a.rect.top.compareTo(b.rect.top);
            return row != 0 ? row : a.rect.left.compareTo(b.rect.left);
          });
    if (nodes.isNotEmpty) {
      nodes.first.requestFocus();
      _scheduleReveal(nodes.first.context!);
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  bool _editing(FocusNode node) =>
      node.context?.widget is EditableText ||
      node.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  List<ScrollableState> _verticalScrolls(BuildContext target) {
    final scrolls = <ScrollableState>[];
    target.visitAncestorElements((element) {
      if (element == context) return false;
      if (element is StatefulElement && element.state is ScrollableState) {
        final scroll = element.state as ScrollableState;
        if (axisDirectionToAxis(scroll.position.axisDirection) ==
            Axis.vertical) {
          scrolls.add(scroll);
        }
      }
      return true;
    });
    return scrolls;
  }

  bool _firstRow(FocusNode node) => !_scope.traversalDescendants.any(
    (candidate) =>
        candidate != node &&
        candidate is! FocusScopeNode &&
        candidate.context?.mounted == true &&
        !candidate.rect.isEmpty &&
        candidate.rect.center.dy < node.rect.top - 1,
  );

  void _top(BuildContext target) {
    for (final scroll in _verticalScrolls(target)) {
      scroll.position.jumpTo(scroll.position.minScrollExtent);
    }
  }

  void _scheduleReveal(BuildContext target) {
    final generation = ++_revealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !target.mounted || generation != _revealGeneration) {
        return;
      }
      final node = FocusManager.instance.primaryFocus;
      if (node == null ||
          node.context?.mounted != true ||
          !_scope.hasFocus ||
          _editing(node)) {
        return;
      }
      if (_firstRow(node)) {
        _top(target);
      } else {
        Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
        );
      }
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node.context?.mounted != true || _editing(node)) {
      return KeyEventResult.ignored;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (down || up) {
      for (final scroll in _verticalScrolls(node.context!)) {
        final viewport = scroll.context.findRenderObject()!;
        final bounds = MatrixUtils.transformRect(
          viewport.getTransformTo(null),
          viewport.paintBounds,
        );
        final clipped = down
            ? node.rect.bottom > bounds.bottom + 1
            : node.rect.top < bounds.top - 1;
        final position = scroll.position;
        final canScroll = down
            ? position.pixels < position.maxScrollExtent
            : position.pixels > position.minScrollExtent;
        if (clipped && canScroll) {
          position.jumpTo(
            (position.pixels +
                    (down ? 1 : -1) * position.viewportDimension * .6)
                .clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          return KeyEventResult.handled;
        }
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _firstRow(node)) {
      _top(node.context!);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        widget.onLeft != null) {
      // Preserve left/right movement inside poster shelves or horizontal rows.
      final hasLeft = _scope.traversalDescendants.any(
        (other) =>
            other != node &&
            other.context?.mounted == true &&
            !other.rect.isEmpty &&
            other.rect.center.dx < node.rect.left &&
            other.rect.bottom > node.rect.top &&
            other.rect.top < node.rect.bottom,
      );
      if (!hasLeft) {
        widget.onLeft!();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    onKeyEvent: _key,
    onFocusChange: (focused) {
      if (focused) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = FocusManager.instance.primaryFocus?.context;
          if (mounted && target != null) _scheduleReveal(target);
        });
      }
    },
    child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(
        requestFocusCallback:
            (node, {alignmentPolicy, alignment, duration, curve}) {
              node.requestFocus();
              if (node.context != null) _scheduleReveal(node.context!);
            },
      ),
      child: widget.child,
    ),
  );
}
