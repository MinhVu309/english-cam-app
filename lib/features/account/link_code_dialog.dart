import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';
import '../../data/account/account_models.dart';
import 'account_widgets.dart';

/// Hiện mã liên kết 8 số kèm đếm ngược. Hết hạn thì cho tạo mã mới.
Future<void> showLinkCodeDialog(
  BuildContext context, {
  required String childName,
  required Future<LinkCode> Function() create,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LinkCodeDialog(childName: childName, create: create),
  );
}

class _LinkCodeDialog extends StatefulWidget {
  const _LinkCodeDialog({required this.childName, required this.create});

  final String childName;
  final Future<LinkCode> Function() create;

  @override
  State<_LinkCodeDialog> createState() => _LinkCodeDialogState();
}

class _LinkCodeDialogState extends State<_LinkCodeDialog> {
  LinkCode? _code;
  String? _error;
  bool _loading = true;
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await widget.create();
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _code = code;
        _left = code.expiresAt.difference(DateTime.now().toUtc());
        _loading = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(
          () => _left = code.expiresAt.difference(DateTime.now().toUtc()),
        );
        if (_left <= Duration.zero) t.cancel();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  String get _countdown {
    final s = _left.inSeconds.clamp(0, 99999);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _code != null && _left <= Duration.zero;
    return AlertDialog(
      title: Text('Thêm máy cho ${widget.childName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            ErrorNote(_error!)
          else ...[
            const Text(
              'Trên máy của bé, mở app, chọn "Máy của bé: nhập mã liên kết" rồi nhập mã này:',
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _code!.pretty,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: expired ? Palette.inkSoft : Palette.orange,
                  decoration: expired ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                expired ? 'Mã đã hết hạn' : 'Hết hạn sau $_countdown',
                style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_code != null && !expired)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _code!.code));
              if (context.mounted) toast(context, 'Đã chép mã.');
            },
            child: const Text('Chép mã'),
          ),
        if (expired || _error != null)
          FilledButton(onPressed: _load, child: const Text('Tạo mã mới')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
