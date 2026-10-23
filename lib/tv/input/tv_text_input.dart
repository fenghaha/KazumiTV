import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/input/remote_input_session.dart';
import 'package:kazumi/tv/input/tv_input_limits.dart';
import 'package:kazumi/tv/platform/tv_native_input.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A remote-friendly field. Browsing focus never starts a keyboard; OK opens a
/// real editor, and that editor owns focus until completion or cancellation.
/// Existing controllers and submitted callbacks remain the source of truth.
class TvTextInput extends StatefulWidget {
  const TvTextInput({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.onSubmitted,
    this.onChanged,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.multiline = false,
    this.maxLength,
    this.focusNode,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool multiline;
  final int? maxLength;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<TvTextInput> createState() => _TvTextInputState();
}

class _TvTextInputState extends State<TvTextInput> {
  final _ownedFocus = FocusNode(debugLabel: 'TV text input');
  final _qrFocus = FocusNode(debugLabel: 'TV phone input');
  bool _focused = false;
  bool _editing = false;

  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  String get _title => widget.label ?? widget.hintText ?? '输入文字';
  int get _maxLength => TvInputLimits.normalize(widget.maxLength);

  @override
  void dispose() {
    _ownedFocus.dispose();
    _qrFocus.dispose();
    super.dispose();
  }

  bool _apply(String value) {
    if (!mounted || !widget.enabled) return false;
    if (value.length > _maxLength) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('内容过长，最多支持 $_maxLength 字符。原内容已保留。')),
      );
      return false;
    }
    var edited = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    for (final formatter in widget.inputFormatters ?? <TextInputFormatter>[]) {
      edited = formatter.formatEditUpdate(widget.controller.value, edited);
    }
    widget.controller.value = edited;
    widget.onChanged?.call(edited.text);
    return true;
  }

  Future<String?> _showEditorDialog(WidgetBuilder builder) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<String>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: builder,
    );
    final result = await navigator.push(route);
    // Route.popped resolves at the start of the reverse transition. Its focus
    // scope can still replace our focus until the route is fully removed.
    await route.completed;
    return result;
  }

  void _restoreFocusAfterFrame(FocusNode Function() node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // onSubmitted may already have opened another route. Never steal focus
      // from it, a newly opened editor, or a field disabled while editing.
      if (!mounted ||
          !widget.enabled ||
          _editing ||
          !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      final target = node();
      if (target.context != null && target.canRequestFocus) {
        target.requestFocus();
      }
    });
  }

  Future<String?> _flutterEditor() => _showEditorDialog(
    (_) => _FlutterEditor(
      title: _title,
      value: widget.controller.text,
      obscureText: widget.obscureText,
      multiline: widget.multiline,
      maxLength: _maxLength,
    ),
  );

  Future<void> _edit() async {
    if (_editing || !widget.enabled) return;
    setState(() => _editing = true);
    String? value;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          value = await TvNativeInput.edit(
            title: _title,
            text: widget.controller.text,
            obscureText: widget.obscureText,
            multiline: widget.multiline,
            maxLength: _maxLength,
          );
        } on MissingPluginException {
          if (mounted) value = await _flutterEditor();
        }
      } else {
        value = await _flutterEditor();
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('输入法暂时无法打开，可使用右侧扫码输入')));
      }
    } finally {
      if (mounted) {
        setState(() => _editing = false);
        _restoreFocusAfterFrame(() => _focus);
      }
    }
    if (value != null && _apply(value) && mounted) {
      widget.onSubmitted?.call(widget.controller.text);
    }
  }

  Future<void> _phone() async {
    if (_editing || !widget.enabled) return;
    setState(() => _editing = true);
    String? result;
    try {
      result = await _showEditorDialog(
        (_) => _PhoneEditor(
          title: _title,
          controller: widget.controller,
          obscureText: widget.obscureText,
          maxLength: _maxLength,
          canApply: () => mounted && widget.enabled,
          onChanged: (value) {
            if (mounted && widget.enabled) _apply(value);
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _editing = false);
        _restoreFocusAfterFrame(() => _qrFocus);
      }
    }
    if (!mounted) return;
    // The phone dialog has closed before this callback can navigate elsewhere.
    if (result != null && widget.enabled) widget.onSubmitted?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    },
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            label: _title,
            button: true,
            enabled: widget.enabled,
            child: Material(
              color: const Color(0xff1c2c41),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                focusNode: _focus,
                autofocus: widget.autofocus,
                canRequestFocus: widget.enabled,
                borderRadius: BorderRadius.circular(16),
                onTap: widget.enabled && !_editing ? _edit : null,
                onFocusChange: (focused) {
                  if (mounted) setState(() => _focused = focused);
                  if (focused) {
                    Scrollable.ensureVisible(
                      context,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 160),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      width: 3,
                      color: _focused
                          ? const Color(0xffebc889)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.keyboard_outlined,
                        color: widget.enabled
                            ? const Color(0xffebc889)
                            : const Color(0xffaab9cb),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: widget.controller,
                          builder: (_, value, _) {
                            final text = value.text.isEmpty
                                ? widget.hintText ?? '按确认键输入'
                                : widget.obscureText
                                ? '••••••••'
                                : value.text;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.label != null)
                                  Text(
                                    widget.label!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xffaab9cb),
                                    ),
                                  ),
                                Text(
                                  text,
                                  maxLines: widget.multiline ? 3 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: value.text.isEmpty || !widget.enabled
                                        ? const Color(0xffaab9cb)
                                        : const Color(0xfff5f1e8),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Tooltip(
          message: '用手机扫码输入',
          child: OutlinedButton.icon(
            focusNode: _qrFocus,
            onPressed: widget.enabled && !_editing ? _phone : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 64),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            icon: const Icon(Icons.qr_code_rounded),
            label: const Text('扫码输入'),
          ),
        ),
      ],
    ),
  );
}

class _FlutterEditor extends StatefulWidget {
  const _FlutterEditor({
    required this.title,
    required this.value,
    required this.obscureText,
    required this.multiline,
    required this.maxLength,
  });
  final String title;
  final String value;
  final bool obscureText;
  final bool multiline;
  final int maxLength;

  @override
  State<_FlutterEditor> createState() => _FlutterEditorState();
}

class _FlutterEditorState extends State<_FlutterEditor> {
  late final _controller = TextEditingController(text: widget.value);
  String? _error;

  void _submit() {
    if (_controller.text.length > widget.maxLength) {
      setState(() => _error = '内容过长，最多支持 ${widget.maxLength} 字符。请缩短后重试。');
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 560,
      child: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        decoration: InputDecoration(
          helperText: '最多支持 ${widget.maxLength} 字符',
          errorText: _error,
        ),
        maxLines: widget.multiline && !widget.obscureText ? 5 : 1,
        textInputAction: widget.multiline
            ? TextInputAction.newline
            : TextInputAction.done,
        onSubmitted: widget.multiline ? null : (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('完成')),
    ],
  );
}

class _PhoneEditor extends StatefulWidget {
  const _PhoneEditor({
    required this.title,
    required this.controller,
    required this.obscureText,
    required this.maxLength,
    required this.canApply,
    required this.onChanged,
  });
  final String title;
  final TextEditingController controller;
  final bool obscureText;
  final int maxLength;
  final bool Function() canApply;
  final ValueChanged<String>? onChanged;

  @override
  State<_PhoneEditor> createState() => _PhoneEditorState();
}

class _PhoneEditorState extends State<_PhoneEditor> {
  RemoteInputSession? _session;
  StreamSubscription<void>? _subscription;
  bool _loading = true;
  bool _starting = false;
  String? _error;
  String? _submittedText;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() => _loading = true);
    await _subscription?.cancel();
    await _session?.close();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
    });
    try {
      final session = await RemoteInputSession.start(
        title: widget.title,
        initialText: widget.controller.text,
        obscureText: widget.obscureText,
        maxLength: widget.maxLength,
        onInput: (text, submit) {
          if (!mounted ||
              _loading ||
              !widget.canApply() ||
              !(ModalRoute.of(context)?.isCurrent ?? false)) {
            return false;
          }
          widget.controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          widget.onChanged?.call(text);
          if (submit) _submittedText = text;
          return true;
        },
      );
      if (!mounted) {
        await session.close();
        return;
      }
      _session = session;
      _subscription = session.submitted.listen(
        (_) {
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            Navigator.of(context).pop(_submittedText);
          }
        },
        onDone: () {
          if (mounted && _session == session) {
            setState(() => _error = '二维码已失效，请刷新后重新扫码');
          }
        },
      );
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '未找到可用的局域网连接。请连接 Wi-Fi 后重试。';
        });
      }
    } finally {
      _starting = false;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('手机输入 · ${widget.title}'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
            else if (_session != null)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: _session!.url.toString(),
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              '手机与电视连接同一网络，扫码后输入。\n关闭此窗口即结束连接。',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, fontSize: 18),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : _start,
        child: const Text('刷新二维码'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('返回电视'),
      ),
    ],
  );
}
