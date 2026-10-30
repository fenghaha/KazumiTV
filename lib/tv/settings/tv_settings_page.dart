import 'package:kazumi/tv/input/tv_remote_input_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/tv/tv_page_scaffold.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/update/tv_update_page.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';

/// TV presentation only; detailed preferences remain in the upstream pages.
class TvSettingsPage extends StatelessWidget {
  const TvSettingsPage({super.key});

  static const revision = String.fromEnvironment(
    'KAZUMI_TV_REVISION',
    defaultValue: 'dev',
  );

  @override
  Widget build(BuildContext context) => TvPageScaffold(
    title: '设置',
    subtitle: '方向键移动 · 确认键选择 · 返回键回到上一页',
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KazumiTV',
                  style: TextStyle(fontSize: 32, color: TvTheme.ink),
                ),
                SizedBox(height: 6),
                Text(
                  '上游基础 ${ApiEndpoints.version}  ·  规则 API ${ApiEndpoints.apiLevel}\n'
                  '电视适配修订 $revision',
                  style: TextStyle(color: TvTheme.muted, height: 1.5),
                ),
              ],
            ),
          ),
          _category(
            context,
            Icons.extension_outlined,
            '规则与播放源',
            '选择、导入与更新规则；首次安装不预装播放源',
            '/tv/rules',
            autofocus: true,
          ),
          _category(
            context,
            Icons.play_circle_outline,
            '播放',
            '解码、渲染与播放行为',
            '/settings/player',
          ),
          _category(
            context,
            Icons.subtitles_outlined,
            '弹幕',
            '弹幕来源、屏蔽与显示效果',
            '/settings/danmaku',
          ),
          _category(
            context,
            Icons.cloud_outlined,
            '同步',
            'Bangumi 与 WebDAV，多设备追番记录',
            '/settings/sync',
          ),
          _category(
            context,
            Icons.language_outlined,
            '网络',
            '访问加速与代理',
            '/settings/proxy',
          ),
          _category(
            context,
            Icons.tune_rounded,
            '高级设置',
            '打开上游完整设置界面',
            '/settings',
          ),
          if (TvUpdateService.supportedBuild) const TvUpdateSettingsTile(),
          const TvRemoteInputAddress(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '电视版安装包由本项目单独发布；规则仍沿用上游版本与兼容性检查。',
              style: TextStyle(color: TvTheme.muted),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _category(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    String route, {
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TvTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TvFocusable(
          autofocus: autofocus,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          onPressed: () => context.pushNamed(route),
          child: Row(
            children: [
              Icon(icon, color: TvTheme.focus, size: 32),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 23)),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(color: TvTheme.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
