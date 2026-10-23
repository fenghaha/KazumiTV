import 'package:flutter/material.dart';
import 'package:kazumi/services/network/danmaku_server.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/input/tv_adaptive_fields.dart';

class DanmakuServerTile extends StatefulWidget {
  const DanmakuServerTile({super.key});
  @override
  State<DanmakuServerTile> createState() => _DanmakuServerTileState();
}

class _DanmakuServerTileState extends State<DanmakuServerTile> {
  Future<void> _edit() async {
    final controller = TextEditingController(
        text: GStorage.getSetting(SettingsKeys.danmakuApiBaseUrl));
    String? error;
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('弹幕服务器'),
        content: SizedBox(width: 560, child: TvAdaptiveTextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '自建弹幕服务地址',
            helperText: '留空使用官方弹弹play（需要构建凭据）',
            errorText: error,
          ),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () {
            try {
              final base = DanmakuServer.normalizeBase(controller.text);
              Navigator.pop(context, DanmakuServer.isOfficial(base) ? '' : base);
            } on FormatException catch (e) {
              update(() => error = e.message.toString());
            }
          }, child: const Text('保存')),
        ],
      )),
    );
    final value = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (!mounted) return;
    if (value != null) {
      await GStorage.putSetting(SettingsKeys.danmakuApiBaseUrl, value);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = GStorage.getSetting(SettingsKeys.danmakuApiBaseUrl);
    final custom = value.trim().isNotEmpty;
    return ListTile(
      title: const Text('弹幕服务器'),
      // A configured base may contain a capability token; do not display it.
      subtitle: Text(custom ? '自建兼容服务 · 重新打开播放页后生效' : '官方弹弹play · 需要构建凭据'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _edit,
    );
  }
}
