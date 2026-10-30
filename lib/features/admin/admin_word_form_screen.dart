import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../account/account_widgets.dart';

/// Thêm ([word] null) hoặc sửa một từ trong bản nháp. Trả true nếu có thay đổi.
///
/// Âm thanh/hình của từ mới phải đã được tải lên máy chủ (Swagger `POST /api/admin/media`); ở đây chỉ chọn tệp có sẵn,
/// vì chọn tệp từ máy cần thêm một thư viện (chưa được duyệt).
class AdminWordFormScreen extends StatefulWidget {
  const AdminWordFormScreen({super.key, this.word, this.service});

  final AdminWord? word;
  final AdminService? service;

  @override
  State<AdminWordFormScreen> createState() => _AdminWordFormScreenState();
}

class _AdminWordFormScreenState extends State<AdminWordFormScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  AdminWord? get _w => widget.word;

  late final _id = TextEditingController(text: _w?.id ?? '');
  late final _en = TextEditingController(text: _w?.en ?? '');
  late final _vi = TextEditingController(text: _w?.vi ?? '');
  late final _phonetic = TextEditingController(text: _w?.phonetic ?? '');
  late final _exampleEn = TextEditingController(text: _w?.exampleEn ?? '');
  late final _exampleVi = TextEditingController(text: _w?.exampleVi ?? '');
  late final _audio = TextEditingController(text: _w?.audio ?? '');
  late final _exampleAudio = TextEditingController(
    text: _w?.exampleAudio ?? '',
  );
  late final _image = TextEditingController(text: _w?.image ?? '');
  late final _emoji = TextEditingController(text: _w?.emoji ?? '');
  String? _category;
  String? _label;
  late bool _hunt = _w?.hunt ?? true;

  List<AdminCategory> _categories = [];
  List<ModelLabel> _labels = [];
  bool _busy = false;
  bool _changed = false;
  String? _error;

  bool get _creating => _w == null;

  @override
  void initState() {
    super.initState();
    _category = _w?.category;
    _label = _w?.label;
    _admin
        .categories()
        .then((c) {
          if (!mounted) return;
          setState(() {
            _categories = c
                .where((x) => !x.isDeleted || x.id == _w?.category)
                .toList();
            _category ??= _categories.isEmpty ? null : _categories.first.id;
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = friendlyError(e));
        });
    _admin
        .modelLabels()
        .then((l) {
          if (mounted) setState(() => _labels = l);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    for (final c in [
      _id,
      _en,
      _vi,
      _phonetic,
      _exampleEn,
      _exampleVi,
      _audio,
      _exampleAudio,
      _image,
      _emoji,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _blank(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _run(
    Future<void> Function() action, {
    bool popAfter = true,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
      if (!mounted) return;
      if (popAfter) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _busy = false);
      }
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
    final draft = WordDraft(
      id: _creating ? _id.text.trim() : null,
      label: _label,
      en: _en.text.trim(),
      vi: _vi.text.trim(),
      phonetic: _phonetic.text.trim(),
      exampleEn: _exampleEn.text.trim(),
      exampleVi: _exampleVi.text.trim(),
      category: _category ?? '',
      audio: _audio.text.trim(),
      exampleAudio: _blank(_exampleAudio),
      image: _blank(_image),
      emoji: _blank(_emoji),
      hunt: _label != null && _hunt,
    );
    if (_creating) {
      await _admin.createWord(draft);
    } else {
      await _admin.updateWord(_w!.id, draft);
    }
  });

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Xoá từ "${_w!.en}"?',
      message:
          'Từ bị ẩn khỏi bản nháp (xoá mềm, khôi phục được). App của bé chỉ mất từ này sau khi bạn xuất bản.',
      confirmLabel: 'Xoá',
    );
    if (ok && mounted) await _run(() => _admin.deleteWord(_w!.id));
  }

  Future<void> _pickMedia(TextEditingController target, String prefix) async {
    List<MediaItem> items;
    try {
      items = await _admin.media(prefix: prefix);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Tệp "$prefix…" trên máy chủ',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text(
                  'Chưa có tệp nào. Tải lên bằng Swagger (POST /api/admin/media) rồi quay lại đây.',
                  style: TextStyle(fontSize: 18),
                ),
              for (final m in items)
                ListTile(
                  title: Text(m.path, style: const TextStyle(fontSize: 18)),
                  subtitle: Text(
                    m.bundled
                        ? 'đóng gói sẵn trong app'
                        : '${(m.size / 1024).ceil()} KB',
                    style: const TextStyle(fontSize: 18),
                  ),
                  onTap: () => Navigator.of(context).pop(m.path),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => target.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AccountScaffold(
        title: _creating ? 'Thêm từ' : 'Sửa từ',
        children: [
          if (w != null && w.isDeleted)
            SectionCard(
              title: 'Từ này đã bị xoá',
              child: BusyButton(
                label: 'Khôi phục',
                busy: _busy,
                onPressed: () => _run(() => _admin.restoreWord(w.id)),
              ),
            ),
          if (_error != null) ErrorNote(_error!),
          if (_creating)
            FieldBox(
              controller: _id,
              label:
                  'Mã (chữ thường, số, _; vd. giraffe) — không đổi được sau này',
            ),
          if (!_creating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Mã: ${w!.id}',
                style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
            ),
          FieldBox(controller: _en, label: 'Tiếng Anh'),
          FieldBox(controller: _vi, label: 'Tiếng Việt'),
          FieldBox(controller: _phonetic, label: 'Phiên âm (vd. /kʌp/)'),
          FieldBox(controller: _exampleEn, label: 'Câu ví dụ (Anh)'),
          FieldBox(controller: _exampleVi, label: 'Câu ví dụ (Việt)'),
          FieldBox(controller: _emoji, label: 'Emoji minh hoạ (tuỳ chọn)'),
          DropdownButtonFormField<String>(
            initialValue: _categories.any((c) => c.id == _category)
                ? _category
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Chủ đề',
              labelStyle: TextStyle(fontSize: 18),
            ),
            style: const TextStyle(fontSize: 20, color: Palette.ink),
            items: [
              for (final c in _categories)
                DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.emoji ?? ''} ${c.vi}'),
                ),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          FieldBox(
            controller: _audio,
            label: 'Âm thanh từ (vd. audio/words/giraffe.mp3)',
            suffix: IconButton(
              tooltip: 'Chọn tệp đã tải lên',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => _pickMedia(_audio, 'audio/words/'),
            ),
          ),
          FieldBox(
            controller: _exampleAudio,
            label: 'Âm thanh câu ví dụ (tuỳ chọn)',
            suffix: IconButton(
              tooltip: 'Chọn tệp đã tải lên',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => _pickMedia(_exampleAudio, 'audio/examples/'),
            ),
          ),
          FieldBox(
            controller: _image,
            label: 'Hình (tuỳ chọn)',
            suffix: IconButton(
              tooltip: 'Chọn tệp đã tải lên',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => _pickMedia(_image, 'images/'),
            ),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _labels.any((l) => l.label == _label) ? _label : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Nhãn nhận diện của model (để trống = chỉ để học)',
              labelStyle: TextStyle(fontSize: 18),
            ),
            style: const TextStyle(fontSize: 20, color: Palette.ink),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Không có'),
              ),
              for (final l in _labels)
                DropdownMenuItem<String?>(
                  value: l.label,
                  enabled: l.usedBy == null || l.usedBy == w?.id,
                  child: Text(
                    l.usedBy == null || l.usedBy == w?.id
                        ? l.label
                        : '${l.label} (đã dùng: ${l.usedBy})',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _label = v),
          ),
          if (_label != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Dùng trong game "Tìm vật"',
                style: TextStyle(fontSize: 20),
              ),
              value: _hunt,
              onChanged: (v) => setState(() => _hunt = v),
            ),
          const SizedBox(height: 12),
          BusyButton(
            label: _creating ? 'Thêm từ' : 'Lưu thay đổi',
            busy: _busy,
            onPressed: _save,
          ),
          if (!_creating && !w!.isDeleted) ...[
            const SizedBox(height: 10),
            BusyButton(
              label: 'Xoá từ',
              outlined: true,
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
