import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation-only navigation between the upstream settings rail and outlet.
class TvSettingsNavigationController extends ChangeNotifier {
  TvSettingsNavigationController() {
    details.addListener(notifyListeners);
    FocusManager.instance.addListener(_remember);
  }
  final details = FocusNode(
    debugLabel: 'TV settings details',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _menu = <String, FocusNode>{};
  FocusNode? _lastDetail;
  Object? _editorOwner;
  VoidCallback? _finishEditor;
  void registerEditor(Object owner, VoidCallback finish) {
    _editorOwner = owner;
    _finishEditor = finish;
  }

  void clearEditor(Object owner) {
    if (identical(owner, _editorOwner)) {
      _editorOwner = null;
      _finishEditor = null;
    }
  }

  bool finishEditing() {
    final finish = _finishEditor;
    _editorOwner = null;
    _finishEditor = null;
    if (finish == null) return false;
    finish();
    return true;
  }

  String _selectedPath = '';
  String get selectedPath => _selectedPath;
  set selectedPath(String value) {
    if (value != _selectedPath) _lastDetail = null;
    _selectedPath = value;
  }

  bool _usable(FocusNode node) {
    final target = node.context;
    return target != null &&
        target.mounted &&
        node.canRequestFocus &&
        node.ancestors.contains(details) &&
        target.findRenderObject()?.attached == true &&
        (ModalRoute.of(target)?.isCurrent ?? true);
  }

  FocusNode menuNode(String path) =>
      _menu.putIfAbsent(path, () => FocusNode(debugLabel: 'TV settings $path'));
  void _remember() {
    final node = FocusManager.instance.primaryFocus;
    if (node != null && node is! FocusScopeNode && _usable(node)) {
      _lastDetail = node;
    }
  }

  bool focusMenu() {
    if (!details.hasFocus) return false;
    menuNode(selectedPath).requestFocus();
    return true;
  }

  void enterDetails() {
    final last = _lastDetail;
    if (last != null && _usable(last)) {
      last.requestFocus();
      return;
    }
    final nodes =
        details.descendants
            .where(
              (node) =>
                  node is! FocusScopeNode &&
                  _usable(node) &&
                  !node.skipTraversal &&
                  !node.rect.isEmpty,
            )
            .toList()
          ..sort((a, b) {
            final vertical = a.rect.top.compareTo(b.rect.top);
            return vertical != 0
                ? vertical
                : a.rect.left.compareTo(b.rect.left);
          });
    if (nodes.isNotEmpty) nodes.first.requestFocus();
  }

  Widget menu(Widget child) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        enterDetails();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
  Widget pane(Widget child) => Focus(
    focusNode: details,
    onKeyEvent: (_, event) {
      final node = FocusManager.instance.primaryFocus;
      final editing =
          node?.context?.widget is EditableText ||
          node?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
      if (!editing &&
          event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        // Let horizontal controls (e.g. Bangumi/WebDAV cards or a field's QR
        // button) reach their left sibling before crossing back to the rail.
        final hasLeft =
            node != null &&
            (node.nearestScope?.traversalDescendants.any(
                  (other) =>
                      other != node &&
                      other is! FocusScopeNode &&
                      other.context?.mounted == true &&
                      !other.rect.isEmpty &&
                      other.rect.center.dx < node.rect.left &&
                      other.rect.bottom > node.rect.top &&
                      other.rect.top < node.rect.bottom,
                ) ??
                false);
        if (hasLeft) return KeyEventResult.ignored;
        focusMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
  @override
  void dispose() {
    FocusManager.instance.removeListener(_remember);
    details.removeListener(notifyListeners);
    details.dispose();
    for (final node in _menu.values) {
      node.dispose();
    }
    super.dispose();
  }
}

class TvSettingsNavigation extends StatelessWidget {
  const TvSettingsNavigation({
    super.key,
    required this.controller,
    required this.innerCanPop,
    required this.onBack,
    required this.child,
  });
  final TvSettingsNavigationController controller;
  final bool Function() innerCanPop;
  final VoidCallback onBack;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => PopScope(
      canPop: !controller.details.hasFocus && !innerCanPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onBack();
      },
      child: TvSettingsEditorScope(controller: controller, child: child),
    ),
  );
}

class TvSettingsEditorScope extends InheritedWidget {
  const TvSettingsEditorScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final TvSettingsNavigationController controller;
  static TvSettingsNavigationController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TvSettingsEditorScope>()
      ?.controller;
  @override
  bool updateShouldNotify(TvSettingsEditorScope oldWidget) =>
      controller != oldWidget.controller;
}
