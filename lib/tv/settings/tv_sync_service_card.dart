import 'package:flutter/material.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

/// Short enough to reveal the action together with the card on a 540p TV pane.
class TvSyncServiceCard extends StatelessWidget {
  const TvSyncServiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.content,
    required this.status,
    required this.action,
    required this.icon,
    required this.onPressed,
  });
  final String title, description, content, action;
  final Widget status;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onPressed: onPressed,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  status,
                ],
              ),
              const SizedBox(height: 6),
              Text(description),
              Text(content, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                '确认键 · $action',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
