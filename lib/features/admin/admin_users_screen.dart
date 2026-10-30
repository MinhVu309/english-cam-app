import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../account/account_widgets.dart';

/// Danh sách tài khoản Admin/Phụ huynh: tìm, lọc theo role, thêm, đổi tên/role, khoá/mở, xoá.
/// Tài khoản của bé không nằm ở đây (phụ huynh quản lý qua hồ sơ bé).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  final _search = TextEditingController();
  String? _role; // null = tất cả
  List<AdminUser> _users = [];
  int _total = 0;
  int _page = 1;
  bool _more = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = append ? _page + 1 : 1;
      final res = await _admin.users(
        search: _search.text.trim(),
        role: _role,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _users = append ? [..._users, ...res.items] : res.items;
        _total = res.total;
        _page = res.page;
        _more = res.hasMore;
        _loading = false;
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

  Future<void> _edit(AdminUser u) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _UserDialog(
        admin: _admin,
        user: u,
        isSelf: u.id == AuthService.instance.parent?.userId,
      ),
    );
    if (changed == true && mounted) _load();
  }

  Future<void> _create() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _UserDialog(admin: _admin),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AccountScaffold(
      title: 'Người dùng',
      onRefresh: _load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Thêm', style: TextStyle(fontSize: 20)),
      ),
      children: [
        FieldBox(
          controller: _search,
          label: 'Tìm theo tên hoặc email',
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          suffix: IconButton(
            tooltip: 'Tìm',
            icon: const Icon(Icons.search_rounded),
            onPressed: _load,
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final (label, value) in const [
              ('Tất cả', null),
              ('Phụ huynh', 'Parent'),
              ('Admin', 'Admin'),
            ])
              ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 18)),
                selected: _role == value,
                onSelected: (_) {
                  _role = value;
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) ErrorNote(_error!),
        if (_loading && _users.isEmpty)
          const Center(child: CircularProgressIndicator()),
        if (!_loading && _error == null && _users.isEmpty)
          const Text(
            'Không có tài khoản nào.',
            style: TextStyle(fontSize: 18, color: Palette.inkSoft),
          ),
        for (final u in _users) _UserTile(u, onTap: () => _edit(u)),
        if (_users.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Đang hiện ${_users.length} / $_total',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
            ),
          ),
        if (_more)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: BusyButton(
              label: 'Tải thêm',
              outlined: true,
              busy: _loading,
              onPressed: () => _load(append: true),
            ),
          ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile(this.user, {required this.onTap});

  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.family_restroom_rounded,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        user.email,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Palette.inkSoft,
                        ),
                      ),
                      Text(
                        '${user.isAdmin ? 'Admin' : 'Phụ huynh'} · ${user.childCount} bé${user.isActive ? '' : ' · ĐÃ KHOÁ'}',
                        style: TextStyle(
                          fontSize: 18,
                          color: user.isActive
                              ? Palette.inkSoft
                              : Palette.orange,
                          fontWeight: user.isActive
                              ? FontWeight.w500
                              : FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hộp thoại thêm ([user] null) hoặc sửa một tài khoản. Trả true nếu có thay đổi.
class _UserDialog extends StatefulWidget {
  const _UserDialog({required this.admin, this.user, this.isSelf = false});

  final AdminService admin;
  final AdminUser? user;
  final bool isSelf;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final _name = TextEditingController(text: widget.user?.fullName ?? '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'Parent';
  late bool _active = widget.user?.isActive ?? true;
  bool _busy = false;
  String? _error;

  bool get _creating => widget.user == null;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
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
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _save() => _run(() async {
    if (_creating) {
      await widget.admin.createUser(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _name.text.trim(),
        role: _role,
      );
    } else {
      await widget.admin.updateUser(
        widget.user!.id,
        fullName: _name.text.trim(),
        role: _role,
        isActive: _active,
      );
    }
  });

  Future<void> _delete() async {
    final u = widget.user!;
    final ok = await confirmDialog(
      context,
      title: 'Xoá tài khoản?',
      message: u.childCount > 0
          ? 'Xoá ${u.fullName} sẽ xoá luôn ${u.childCount} hồ sơ bé và toàn bộ tiến độ của các bé. Không hoàn tác được.'
          : 'Xoá ${u.fullName}. Không hoàn tác được.',
      confirmLabel: 'Xoá',
    );
    if (ok && mounted) await _run(() => widget.admin.deleteUser(u.id));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? 'Thêm tài khoản' : 'Sửa tài khoản'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_creating)
              FieldBox(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
            if (!_creating)
              Text(
                widget.user!.email,
                style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
            if (!_creating) const SizedBox(height: 10),
            FieldBox(controller: _name, label: 'Họ tên'),
            if (_creating)
              FieldBox(
                controller: _password,
                label: 'Mật khẩu (≥ 8 ký tự, có chữ thường và số)',
                obscure: true,
              ),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Vai trò',
                labelStyle: TextStyle(fontSize: 18),
              ),
              style: const TextStyle(fontSize: 20, color: Palette.ink),
              items: const [
                DropdownMenuItem(value: 'Parent', child: Text('Phụ huynh')),
                DropdownMenuItem(value: 'Admin', child: Text('Admin')),
              ],
              onChanged: widget.isSelf
                  ? null
                  : (v) => setState(() => _role = v ?? _role),
            ),
            if (!_creating)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _active ? 'Đang hoạt động' : 'Đã khoá',
                  style: const TextStyle(fontSize: 20),
                ),
                value: _active,
                onChanged: widget.isSelf
                    ? null
                    : (v) => setState(() => _active = v),
              ),
            if (widget.isSelf)
              const Text(
                'Đây là tài khoản của bạn: không tự đổi vai trò, khoá hay xoá chính mình được.',
                style: TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ErrorNote(_error!),
              ),
          ],
        ),
      ),
      actions: [
        if (!_creating && !widget.isSelf)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('Xoá', style: TextStyle(color: Palette.orange)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_creating ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}
