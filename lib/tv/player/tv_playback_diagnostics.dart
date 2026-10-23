import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Reads only non-sensitive playback counters while the information sheet is open.
class TvPlaybackDiagnostics extends StatefulWidget {
  const TvPlaybackDiagnostics({super.key, required this.player});

  final Player? Function() player;

  @override
  State<TvPlaybackDiagnostics> createState() => _TvPlaybackDiagnosticsState();
}

class _TvPlaybackDiagnosticsState extends State<TvPlaybackDiagnostics> {
  Timer? _timer;
  bool _reading = false;
  String _status = '正在读取播放状态';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_reading) return;
    final player = widget.player();
    final native = player?.platform;
    if (native is! NativePlayer) return;
    _reading = true;
    try {
      final values = <String, String>{};
      for (final property in const [
        'hwdec-current',
        'current-vo',
        'demuxer-cache-duration',
        'demuxer-cache-state',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'avsync',
        'paused-for-cache',
        'time-pos',
      ]) {
        values[property] = await native.getProperty(
          property,
          waitForInitialization: false,
        );
      }
      if (!mounted || !identical(widget.player(), player)) return;
      setState(() => _status = formatTvPlaybackDiagnostics(values));
    } catch (_) {
      // A disposed/replaced player or unsupported property has no UI side effect.
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_status, style: Theme.of(context).textTheme.bodySmall);
}

/// Cache packet metadata is not the number of media bytes held on disk.
/// Keep unknown properties visibly unknown, and never display arbitrary JSON.
String formatTvPlaybackDiagnostics(Map<String, String> values) {
  Map<dynamic, dynamic> cache = const {};
  try {
    final decoded = jsonDecode(values['demuxer-cache-state'] ?? '');
    if (decoded is Map) cache = decoded;
  } on FormatException {
    // Older mpv versions can omit this property.
  }
  String value(String key) => switch (values[key]) {
    null || '' => '—',
    final text => text,
  };
  String number(Object? raw, {double scale = 1}) {
    final parsed = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return parsed != null && parsed.isFinite
        ? (parsed * scale).toStringAsFixed(2)
        : '—';
  }

  final rate = cache['raw-input-rate'];
  return '硬解: ${value('hwdec-current')}  输出: ${value('current-vo')}\n'
      '读取: ${number(rate, scale: 1 / 1000000)} MB/s '
      '(${number(rate, scale: 8 / 1000000)} Mbps)\n'
      '缓存: ${number(values['demuxer-cache-duration'])} 秒  '
      '缓冲暂停: ${value('paused-for-cache')}  '
      '位置: ${number(values['time-pos'])} 秒\n'
      '渲染丢帧: ${value('frame-drop-count')}  '
      '解码丢帧: ${value('decoder-frame-drop-count')}  '
      '声画差: ${number(values['avsync'])} 秒\n'
      '缓存文件: ${number(cache['file-cache-bytes'], scale: 1 / 1048576)} MiB';
}
