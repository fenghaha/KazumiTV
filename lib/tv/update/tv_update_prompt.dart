import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

/// Uses its own TV theme because the root navigator can have a mobile theme.
Future<bool> showTvUpdatePrompt(
  BuildContext context, {
  required String revision,
}) async {
  final previous = FocusManager.instance.primaryFocus;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    builder: (_) => Theme(
      data: TvTheme.dark,
      child: TvUpdatePromptDialog(revision: revision),
    ),
  );
  final accepted = await navigator.push(route);
  await route.completed;
  if (previous?.context?.mounted == true && previous!.canRequestFocus) {
    previous.requestFocus();
  }
  return accepted == true;
}

class TvUpdatePromptDialog extends StatelessWidget {
  const TvUpdatePromptDialog({super.key, required this.revision});
  final String revision;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop(false);
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: TvTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.system_update_rounded,
                        color: TvTheme.focus,
                        size: 32,
                      ),
                      SizedBox(width: 14),
                      Text(
                        '发现新版本',
                        style: TextStyle(color: TvTheme.ink, fontSize: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'KazumiTV $revision 已发布',
                    style: const TextStyle(color: TvTheme.ink, fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '可前往软件更新查看详情。现有设置与观看记录会保留。',
                    style: TextStyle(color: TvTheme.muted, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  FocusTraversalGroup(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TvFocusable(
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(false),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          child: const Text(
                            '稍后',
                            style: TextStyle(color: TvTheme.ink, fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 16),
                        TvFocusable(
                          onPressed: () => Navigator.of(context).pop(true),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          child: const Text(
                            '查看更新',
                            style: TextStyle(color: TvTheme.ink, fontSize: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
