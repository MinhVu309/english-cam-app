import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../account/account_widgets.dart';

/// Kiểm tra bản nháp từ vựng rồi xuất bản: từ lúc đó app của bé mới thấy thay đổi (qua "Cập nhật từ vựng").
/// Máy chủ từ chối nếu nháp sai (thiếu tệp âm thanh, nhãn lạ…) hoặc không có gì thay đổi.
class AdminPublishScreen extends StatefulWidget {
  const AdminPublishScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminPublishScreen> createState() => _AdminPublishScreenState();
}

class _AdminPublishScreenState extends State<AdminPublishScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  final _notes = TextEditingController();
  VocabStatus? _status;
  List<String>? _errors;
  List<ReleaseInfo> _releases = [];
  String? _loadError;
  String? _publishError;
  String? _done;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final status = await _admin.vocabStatus();
      final errors = await _admin.validate();
      final releases = await _admin.releases();
      if (mounted) {
        setState(() {
          _status = status;
          _errors = errors;
          _releases = releases;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  Future<void> _publish() async {
    final ok = await confirmDialog(
      context,
      title: 'Xuất bản?',
      message:
          'App của mọi bé sẽ nhận bản từ vựng này khi bấm "Cập nhật từ vựng".',
      confirmLabel: 'Xuất bản',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _publishError = null;
      _done = null;
    });
    try {
      final r = await _admin.publish(
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      _notes.clear();
      if (mounted) {
        setState(
          () =>
              _done = 'Đã xuất bản phiên bản ${r.version} (${r.wordCount} từ).',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _publishError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final errors = _errors;
    return AccountScaffold(
      title: 'Xuất bản',
      onRefresh: _load,
      children: [
        if (_loadError != null) ErrorNote(_loadError!),
        if (s == null && _loadError == null)
          const Center(child: CircularProgressIndicator()),
        if (s != null)
          SectionCard(
            title: 'Trạng thái',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang phát: phiên bản ${s.publishedVersion ?? '—'}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.hasUnpublishedChanges
                      ? 'Bản nháp có thay đổi chưa xuất bản.'
                      : 'Bản nháp trùng với bản đang phát.',
                  style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
                ),
                Text(
                  '${s.activeWords} từ · ${s.activeCategories} chủ đề trong bản nháp',
                  style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
                ),
              ],
            ),
          ),
        if (errors != null && errors.isNotEmpty)
          SectionCard(
            title: 'Bản nháp chưa hợp lệ (${errors.length} lỗi)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $e', style: const TextStyle(fontSize: 18)),
                  ),
              ],
            ),
          ),
        if (errors != null && errors.isEmpty && s != null)
          SectionCard(
            title: 'Xuất bản',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bản nháp hợp lệ.', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 10),
                FieldBox(
                  controller: _notes,
                  label: 'Ghi chú phiên bản (tuỳ chọn)',
                  maxLength: 500,
                ),
                if (_publishError != null) ErrorNote(_publishError!),
                if (_done != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _done!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Palette.teal,
                      ),
                    ),
                  ),
                BusyButton(
                  label: 'Xuất bản',
                  icon: Icons.publish_rounded,
                  busy: _busy,
                  onPressed: _publish,
                ),
              ],
            ),
          ),
        if (_releases.isNotEmpty)
          SectionCard(
            title: 'Các phiên bản đã phát',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _releases.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'v${r.version} · ${r.wordCount} từ · ${relativeTime(r.createdAt, DateTime.now())}${r.notes == null ? '' : '\n${r.notes}'}',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
