import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import 'account_widgets.dart';
import 'login_screen.dart';

/// Quên mật khẩu: bước 1 nhập email nhận mã, bước 2 nhập mã + mật khẩu mới (xong là đăng nhập luôn).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Email không hợp lệ.');
      return;
    }
    await _run(() async {
      await AuthService.instance.forgotPassword(_email.text);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _reset() async {
    final problem = passwordProblem(_password.text);
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Nhập đủ mã 6 số.');
      return;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _run(() async {
      await AuthService.instance.resetPassword(
        _email.text,
        _code.text,
        _password.text,
      );
      if (!mounted) return;
      toast(context, 'Đã đổi mật khẩu và đăng nhập.');
      goToLanding(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AccountScaffold(
      title: 'Quên mật khẩu',
      children: [
        Text(
          _codeSent
              ? 'Nếu email có tài khoản, mã 6 số đã được gửi tới ${_email.text.trim()}. Nhập mã và mật khẩu mới.'
              : 'Nhập email đã đăng ký, chúng tôi sẽ gửi mã 6 số để đặt lại mật khẩu.',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_error != null) ErrorNote(_error!),
        FieldBox(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          enabled: !_busy && !_codeSent,
        ),
        if (!_codeSent)
          BusyButton(label: 'Gửi mã', busy: _busy, onPressed: _sendCode)
        else ...[
          FieldBox(
            controller: _code,
            label: 'Mã 6 số',
            centered: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !_busy,
          ),
          FieldBox(
            controller: _password,
            label: 'Mật khẩu mới (≥ 8 ký tự, có chữ thường và số)',
            obscure: true,
            enabled: !_busy,
          ),
          BusyButton(label: 'Đổi mật khẩu', busy: _busy, onPressed: _reset),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _codeSent = false),
            child: const Text('Dùng email khác'),
          ),
        ],
      ],
    );
  }
}
