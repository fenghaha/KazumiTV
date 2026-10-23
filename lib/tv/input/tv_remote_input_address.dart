import 'package:flutter/material.dart';
import 'package:kazumi/tv/input/remote_input_service.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvRemoteInputAddress extends StatefulWidget {
  const TvRemoteInputAddress({super.key});
  @override
  State<TvRemoteInputAddress> createState() => _TvRemoteInputAddressState();
}

class _TvRemoteInputAddressState extends State<TvRemoteInputAddress> {
  late Future<Uri?> _address = TvMode.enabled
      ? RemoteInputService.instance.ensureStarted()
      : Future.value(null);
  @override
  Widget build(BuildContext context) => TvFocusable(
    onPressed: () =>
        setState(() => _address = RemoteInputService.instance.ensureStarted()),
    child: FutureBuilder<Uri?>(
      future: _address,
      builder: (context, result) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('手机 / 电脑远程输入', style: TextStyle(fontSize: 23)),
          const SizedBox(height: 8),
          Text(
            result.hasError
                ? '远程输入未启动，请检查网络或端口 8765；按确认重试。'
                : result.data?.toString() ?? '正在获取远程输入地址…',
          ),
          const Text('收藏地址后无需反复扫码。在电视选中输入框，即可从网页发送。'),
        ],
      ),
    ),
  );
}
