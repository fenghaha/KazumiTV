import 'package:flutter/material.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_scroll_boundary.dart';

class TvPageScaffold extends StatelessWidget {
  const TvPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    backgroundColor: TvTheme.background,
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (subtitle != null) ...[
              Text(subtitle!, style: const TextStyle(color: TvTheme.muted)),
              const SizedBox(height: 20),
            ],
            Expanded(child: TvScrollBoundary(child: child)),
          ],
        ),
      ),
    ),
  );
}
