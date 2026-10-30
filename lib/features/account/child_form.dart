import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_widgets.dart';

typedef ChildFormSubmit =
    Future<void> Function(String nickname, String? avatarKey, int? birthYear);

/// Biệt danh + avatar + năm sinh (tuỳ chọn) của một bé. Dùng cho cả thêm mới và chỉnh sửa.
class ChildForm extends StatefulWidget {
  const ChildForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.initialNickname = '',
    this.initialAvatar,
    this.initialBirthYear,
  });

  final String submitLabel;
  final ChildFormSubmit onSubmit;
  final String initialNickname;
  final String? initialAvatar;
  final int? initialBirthYear;

  @override
  State<ChildForm> createState() => _ChildFormState();
}

class _ChildFormState extends State<ChildForm> {
  late final TextEditingController _nickname = TextEditingController(
    text: widget.initialNickname,
  );
  late final TextEditingController _year = TextEditingController(
    text: widget.initialBirthYear?.toString() ?? '',
  );
  late String? _avatar = widget.initialAvatar ?? kAvatars.keys.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _nickname.text.trim();
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    if (nickname.isEmpty || nickname.length > 30) {
      setState(() => _error = 'Biệt danh cần từ 1 đến 30 ký tự.');
      return;
    }
    if (yearText.isNotEmpty &&
        (year == null || year < 2000 || year > DateTime.now().year)) {
      setState(() => _error = 'Năm sinh không hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(nickname, _avatar, year);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ErrorNote(_error!),
        FieldBox(
          controller: _nickname,
          label: 'Biệt danh của bé',
          maxLength: 30,
          textInputAction: TextInputAction.next,
          enabled: !_busy,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Chọn hình đại diện', style: TextStyle(fontSize: 18)),
        ),
        AvatarPicker(
          value: _avatar,
          onChanged: (v) => setState(() => _avatar = v),
        ),
        const SizedBox(height: 16),
        FieldBox(
          controller: _year,
          label: 'Năm sinh (không bắt buộc)',
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_busy,
        ),
        BusyButton(label: widget.submitLabel, busy: _busy, onPressed: _submit),
      ],
    );
  }
}
