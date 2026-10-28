import 'package:flutter/material.dart';
import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/settings/tv_choice_dialog.dart';

/// Keep TV navigation/confirmation separate from RadioGroup's arrow selection.
Future<bool> selectTvAccelerationMode<T extends AccelerationMode>(
  BuildContext context, {
  required String title,
  required T current,
  required List<T> modes,
  required SettingKey<String> setting,
}) async {
  T? selected;
  await showTvChoices(
    context,
    title: Text(title),
    choices: [
      for (final mode in modes)
        TvChoice(
          selected: mode == current,
          onSelected: () => selected = mode,
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mode.label),
              Text(
                mode.description,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
    ],
  );
  final value = selected;
  if (!context.mounted || value == null || value == current) return false;
  await GStorage.putSetting(setting, value.name);
  return true;
}
