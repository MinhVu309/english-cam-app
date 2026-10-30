import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../account/account_widgets.dart';

/// Chủ đề từ vựng: xem, thêm, sửa tên/emoji/màu, xoá (chỉ khi không còn từ) và khôi phục.
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  List<AdminCategory>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await _admin.categories();
      if (mounted) setState(() => _items = c);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _edit(AdminCategory? c) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(admin: _admin, category: c),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AccountScaffold(
      title: 'Chủ đề',
      onRefresh: _load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm chủ đề', style: TextStyle(fontSize: 20)),
      ),
      children: [
        if (_error != null) ErrorNote(_error!),
        if (items == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        for (final c in items ?? const <AdminCategory>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: c.isDeleted ? Palette.oops : Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _edit(c),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          c.emoji ?? '📁',
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.vi} · ${c.en}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${c.id} · ${c.wordCount} từ${c.isDeleted ? ' · ĐÃ XOÁ' : ''}',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Palette.inkSoft,
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
          ),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.admin, this.category});

  final AdminService admin;
  final AdminCategory? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _id = TextEditingController(text: widget.category?.id ?? '');
  late final _vi = TextEditingController(text: widget.category?.vi ?? '');
  late final _en = TextEditingController(text: widget.category?.en ?? '');
  late final _emoji = TextEditingController(text: widget.category?.emoji ?? '');
  late final _color = TextEditingController(text: widget.category?.color ?? '');
  bool _busy = false;
  String? _error;

  bool get _creating => widget.category == null;

  @override
  void dispose() {
    for (final c in [_id, _vi, _en, _emoji, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _blank(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

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
      await widget.admin.createCategory(
        id: _id.text.trim(),
        vi: _vi.text.trim(),
        en: _en.text.trim(),
        emoji: _blank(_emoji),
        color: _blank(_color),
      );
    } else {
      await widget.admin.updateCategory(
        widget.category!.id,
        vi: _vi.text.trim(),
        en: _en.text.trim(),
        emoji: _blank(_emoji),
        color: _blank(_color),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return AlertDialog(
      title: Text(_creating ? 'Thêm chủ đề' : 'Sửa chủ đề'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_creating)
              FieldBox(controller: _id, label: 'Mã (chữ thường, số, _)'),
            FieldBox(controller: _vi, label: 'Tên tiếng Việt'),
            FieldBox(controller: _en, label: 'Tên tiếng Anh'),
            FieldBox(controller: _emoji, label: 'Emoji (tuỳ chọn)'),
            FieldBox(controller: _color, label: 'Màu #RRGGBB (tuỳ chọn)'),
            if (_error != null) ErrorNote(_error!),
          ],
        ),
      ),
      actions: [
        if (c != null && c.isDeleted)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => widget.admin.restoreCategory(c.id)),
            child: const Text('Khôi phục'),
          ),
        if (c != null && !c.isDeleted)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => widget.admin.deleteCategory(c.id)),
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
