import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
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
  Widget build(BuildContext context) {
    if (SettingsPaneScope.of(context)?.embedded == true) {
      return SettingsDetailScaffold(
        title: Text(title),
        actions: actions,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: child,
        ),
      );
    }
    return Scaffold(
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
}
