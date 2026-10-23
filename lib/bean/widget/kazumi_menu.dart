import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/settings/tv_choice_dialog.dart';
import 'package:flutter/material.dart';

typedef KazumiMenuBuilder =
    Widget Function(BuildContext context, VoidCallback? toggle);

const _menuItemStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(144, 48)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  alignment: AlignmentDirectional.centerStart,
  visualDensity: VisualDensity.standard,
);

class KazumiMenuButton extends StatelessWidget {
  const KazumiMenuButton({
    super.key,
    required this.builder,
    required this.menuChildren,
    this.controller,
    this.enabled = true,
    this.animated = false,
    this.crossAxisUnconstrained = true,
    this.onOpen,
    this.onClose,
    this.style,
  });

  final KazumiMenuBuilder builder;
  final List<Widget> menuChildren;
  final MenuController? controller;
  final bool enabled;

  /// Opt in only for menus that previously animated.
  final bool animated;
  final bool crossAxisUnconstrained;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final MenuStyle? style;

  @override
  Widget build(BuildContext context) {
    if (TvMode.enabled) {
      return builder(context, enabled && menuChildren.isNotEmpty ? () async {
        onOpen?.call();
        try {
          await showTvChoices(context, title: const Text('选择操作'), choices: _tvChoices(context, menuChildren));
        } finally {
          onClose?.call();
        }
      } : null);
    }
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        // Submenu entries must use the same inset as ordinary menu items.
        style: _menuItemStyle.merge(MenuButtonTheme.of(context).style),
      ),
      child: MenuAnchor(
        controller: controller,
        consumeOutsideTap: true,
        crossAxisUnconstrained: crossAxisUnconstrained,
        animated: animated && !MediaQuery.disableAnimationsOf(context),
        onOpen: onOpen,
        onClose: onClose,
        style: style,
        menuChildren: menuChildren,
        builder: (context, controller, _) => builder(
          context,
          enabled && menuChildren.isNotEmpty
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
        ),
      ),
    );
  }
}

class KazumiMenuItem extends StatelessWidget {
  const KazumiMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.selected,
    this.destructive = false,
    this.requestFocusOnHover = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;

  /// Null for actions; a bool exposes single-choice selection semantics.
  final bool? selected;
  final bool destructive;
  final bool requestFocusOnHover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive
        ? colors.error
        : selected == true
        ? colors.primary
        : null;
    final foregroundColor = color == null
        ? null
        : WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.disabled) ? null : color,
          );
    return MenuItemButton(
      onPressed: onPressed,
      requestFocusOnHover: requestFocusOnHover,
      style: ButtonStyle(
        foregroundColor: foregroundColor,
        iconColor: foregroundColor,
      ),
      leadingIcon: leadingIcon,
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: selected == null ? null : true,
        child: Text(label, textAlign: TextAlign.start),
      ),
    );
  }
}

List<TvChoice> _tvChoices(BuildContext context, List<Widget> items) => [
  for (final item in items)
    if (item is KazumiMenuItem)
      TvChoice(label: Text(item.label), icon: item.leadingIcon,
        selected: item.selected == true, onSelected: item.onPressed)
    else if (item is SubmenuButton)
      TvChoice(label: item.child ?? const Text('更多选项'), icon: item.leadingIcon,
        onSelected: () => showTvChoices(context, title: item.child ?? const Text('更多选项'), choices: _tvChoices(context, item.menuChildren)))
    else if (item is MenuItemButton)
      TvChoice(label: item.child ?? const SizedBox.shrink(), icon: item.leadingIcon, onSelected: item.onPressed),
];
