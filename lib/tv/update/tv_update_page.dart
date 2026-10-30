import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:kazumi/tv/tv_page_scaffold.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/update/tv_update_manifest.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

Future<void> showTvUpdates([BuildContext? context]) async {
  final target = context ?? rootNavigatorKey.currentContext;
  if (target == null || !target.mounted) return;
  await Navigator.of(
    target,
  ).push<void>(MaterialPageRoute(builder: (_) => const TvUpdatePage()));
}

class TvUpdateSettingsTile extends StatelessWidget {
  const TvUpdateSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TvUpdateService.instance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TvTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) => TvFocusable(
            onPressed: () => showTvUpdates(context),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  color: TvTheme.focus,
                  size: 32,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('软件更新', style: TextStyle(fontSize: 23)),
                      const SizedBox(height: 3),
                      Text(
                        service.available == null
                            ? '检查并安装 KazumiTV 电视版更新'
                            : '发现新版 ${service.manifest!.revision}，可下载更新',
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
      ),
    );
  }
}

class TvUpdatePage extends StatefulWidget {
  const TvUpdatePage({super.key, this.service});
  final TvUpdateService? service;

  @override
  State<TvUpdatePage> createState() => _TvUpdatePageState();
}

class _TvUpdatePageState extends State<TvUpdatePage>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? TvUpdateService.instance;
  bool _checking = true;
  bool _downloading = false;
  bool _canInstall = false;
  double? _progress;
  String _status = '正在检查更新…';
  String? _downloadedPath;
  CancelToken? _cancel;
  TvUpdateAsset? _downloadedAsset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    try {
      final allowed = await _service.canInstall();
      if (mounted) setState(() => _canInstall = allowed);
    } catch (_) {
      /* A check or install shows actionable platform errors. */
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = '正在检查更新…';
    });
    try {
      await _service.check();
      if (!mounted) return;
      _downloadedPath = null;
      _downloadedAsset = null;
      setState(() {
        _status = _service.available == null
            ? '当前没有可安装的更新'
            : '发现新版 ${_service.manifest!.revision}';
      });
      await _refreshPermission();
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message.toString()
              : '检查更新失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download() async {
    final asset = _service.available;
    if (asset == null || _downloading) return;
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _downloading = true;
      _progress = null;
      _status = '正在下载更新…';
    });
    try {
      final path = await _service.download(
        asset: asset,
        cancel: cancel,
        onProgress: (received, total) {
          if (mounted && !cancel.isCancelled) {
            setState(() {
              _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
              _status = total > 0 && received >= total ? '正在校验安装包…' : '正在下载更新…';
            });
          }
        },
      );
      if (!mounted || cancel.isCancelled) return;
      _downloadedPath = path;
      _downloadedAsset = asset;
      await _refreshPermission();
      if (mounted) {
        setState(
          () => _status = _canInstall
              ? '下载完成，文件与签名校验通过，可安装更新'
              : '下载完成，请先允许 KazumiTV 安装应用',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = cancel.isCancelled
              ? '已取消下载，可重新尝试'
              : error is FormatException
              ? error.message.toString()
              : error is PlatformException
              ? (error.message ?? '安装包验证失败')
              : getUpdateDownloadErrorMessage(error),
        );
      }
    } finally {
      _cancel = null;
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final path = _downloadedPath;
    final asset = _downloadedAsset;
    if (path == null || asset == null) return;
    try {
      if (!await _service.canInstall()) {
        await _service.openInstallSettings();
        if (mounted) setState(() => _status = '允许安装后返回此页，选择“安装更新”');
        return;
      }
      await _service.install(path, asset);
      if (mounted) setState(() => _status = '请在系统界面确认安装；更新会保留现有数据');
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is PlatformException
              ? (error.message ?? '无法安装更新')
              : error is FormatException
              ? error.message.toString()
              : '无法打开系统安装界面，请重试',
        );
      }
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('Update page closed');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = _service.installed;
    final manifest = _service.manifest;
    final asset = _service.available;
    final busy = _checking || _downloading;
    return TvPageScaffold(
      title: '软件更新',
      subtitle: 'KazumiTV 电视版 · 本项目 GitHub 发布',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前版本 ${installed?.versionName ?? ''} · ${TvUpdateService.revision}',
              style: const TextStyle(fontSize: 25, color: TvTheme.ink),
            ),
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Text(
                _status,
                style: const TextStyle(fontSize: 23, color: TvTheme.focus),
              ),
            ),
            if (_downloading) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? '正在连接…'
                    : '${(_progress! * 100).toStringAsFixed(0)}%',
              ),
            ],
            if (asset != null && manifest != null) ...[
              const SizedBox(height: 20),
              Text(
                '${manifest.version} · ${manifest.revision} · '
                '${(asset.size / 1024 / 1024).toStringAsFixed(1)} MB',
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 12),
              Text(
                manifest.notes,
                style: const TextStyle(color: TvTheme.muted, height: 1.5),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                TvFocusable(
                  autofocus: true,
                  focusableWhenDisabled: true,
                  onPressed: busy ? null : _check,
                  child: const Text('检查更新'),
                ),
                if (asset != null && _downloadedPath == null)
                  TvFocusable(
                    focusableWhenDisabled: true,
                    onPressed: busy ? null : _download,
                    child: const Text('下载更新'),
                  ),
                if (_downloadedPath != null)
                  TvFocusable(
                    onPressed: busy ? null : _install,
                    child: Text(_canInstall ? '安装更新' : '允许安装更新'),
                  ),
                if (_downloading)
                  TvFocusable(
                    onPressed: () => _cancel?.cancel('Cancelled by user'),
                    child: const Text('取消下载'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              '应用会选择适合此设备的安装包，并检查文件与签名。'
              '安装需在 Android 系统界面确认，现有设置与观看记录会保留。',
              style: TextStyle(color: TvTheme.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
