import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvChoice {
  const TvChoice({
    required this.label,
    this.onSelected,
    this.selected = false,
    this.icon,
  });
  final Widget label;
  final VoidCallback? onSelected;
  final bool selected;
  final Widget? icon;
}

Future<void> showTvChoices(
  BuildContext context, {
  required Widget title,
  required List<TvChoice> choices,
}) async {
  final previous = FocusManager.instance.primaryFocus;
  final enabled = choices.where((item) => item.onSelected != null).toList();
  final initial =
      enabled.where((item) => item.selected).firstOrNull ?? enabled.firstOrNull;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<VoidCallback>(
    context: context,
    builder: (dialogContext) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              navigator.pop();
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: title,
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in choices)
                    TvFocusable(
                      autofocus: identical(choice, initial),
                      selected: choice.selected,
                      onPressed: choice.onSelected == null
                          ? null
                          : () => navigator.pop(choice.onSelected),
                      child: Row(
                        children: [
                          if (choice.icon != null) ...[
                            choice.icon!,
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: choice.label),
                          if (choice.selected) const Icon(Icons.check),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TvFocusable(
              onPressed: () => navigator.pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  );
  final action = await navigator.push(route);
  await route.completed;
  if (!context.mounted) return;
  if (previous?.context?.mounted == true && previous!.canRequestFocus) {
    previous.requestFocus();
  }
  action?.call();
}
