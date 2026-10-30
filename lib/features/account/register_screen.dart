import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../services/auth_service.dart';
import 'account_widgets.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    String? problem;
    if (name.length < 2) {
      problem = 'Nhập họ tên (ít nhất 2 ký tự).';
    } else if (!isValidEmail(_email.text)) {
      problem = 'Email không hợp lệ.';
    } else {
      problem = passwordProblem(_password.text);
    }
    if (problem == null && _password.text != _confirm.text) {
      problem = 'Mật khẩu nhập lại không khớp.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.register(_email.text, _password.text, name);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        Routes.otp,
        arguments: OtpArgs(_email.text.trim(), OtpMode.register),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountScaffold(
      title: 'Đăng ký',
      children: [
        const Text(
          'Tạo tài khoản phụ huynh. Chúng tôi sẽ gửi mã 6 số tới email để xác minh.',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_error != null) ErrorNote(_error!),
        FieldBox(
          controller: _name,
          label: 'Họ và tên',
          textInputAction: TextInputAction.next,
          enabled: !_busy,
        ),
        FieldBox(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_busy,
        ),
        FieldBox(
          controller: _password,
          label: 'Mật khẩu (≥ 8 ký tự, có chữ thường và số)',
          obscure: true,
          textInputAction: TextInputAction.next,
          enabled: !_busy,
        ),
        FieldBox(
          controller: _confirm,
          label: 'Nhập lại mật khẩu',
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          enabled: !_busy,
        ),
        BusyButton(label: 'Đăng ký', busy: _busy, onPressed: _submit),
      ],
    );
  }
}
