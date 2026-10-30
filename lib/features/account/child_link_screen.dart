import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../mascot/mascot.dart';
import 'account_widgets.dart';

/// Trên máy của bé: nhập mã 8 số do bố mẹ tạo để liên kết máy này với hồ sơ của bé. Không cần tài khoản.
class ChildLinkScreen extends StatefulWidget {
  const ChildLinkScreen({super.key});

  @override
  State<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

class _ChildLinkScreenState extends State<ChildLinkScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final digits = _code.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      setState(() => _error = 'Nhập đủ mã 8 số.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.linkWithCode(digits);
      if (!mounted) return;
      toast(
        context,
        'Đã liên kết với ${AuthService.instance.activeChild?.nickname ?? 'bé'}!',
      );
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountScaffold(
      title: 'Máy của bé',
      children: [
        const Center(child: Mascot(size: 96, animate: false)),
        const SizedBox(height: 8),
        const Text(
          'Nhờ bố mẹ mở app trên máy của họ: Hồ sơ của bé → Quản lý → "Thêm máy cho bé", rồi nhập mã 8 số vào đây.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_error != null) ErrorNote(_error!),
        FieldBox(
          controller: _code,
          label: 'Mã liên kết',
          centered: true,
          maxLength: 9,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _link(),
          enabled: !_busy,
        ),
        BusyButton(label: 'Liên kết', busy: _busy, onPressed: _link),
      ],
    );
  }
}
