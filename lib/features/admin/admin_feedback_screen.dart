import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../account/account_widgets.dart';

/// Góp ý khi app nhận diện sai (bé/phụ huynh chọn lại hoặc gõ tên đúng): model hay nhầm gì, người dùng muốn thêm từ nào.
/// Chỉ có chữ, không có ảnh. Admin xoá được từng góp ý và chép CSV.
class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  FeedbackSummary? _summary;
  List<AdminFeedback> _items = [];
  int _total = 0;
  int _page = 1;
  bool _more = false;
  bool _unknownOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = append ? _summary : await _admin.feedbackSummary();
      final page = await _admin.feedback(
        unknownOnly: _unknownOnly,
        page: append ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _items = append ? [..._items, ...page.items] : page.items;
        _total = page.total;
        _page = page.page;
        _more = page.hasMore;
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

  Future<void> _delete(AdminFeedback f) async {
    final ok = await confirmDialog(
      context,
      title: 'Xoá góp ý này?',
      message:
          '"${f.predictedLabel}" → "${f.correctText}". Không hoàn tác được.',
      confirmLabel: 'Xoá',
    );
    if (!ok || !mounted) return;
    try {
      await _admin.deleteFeedback(f.id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _copyCsv() async {
    try {
      final csv = await _admin.feedbackCsv();
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) {
        toast(
          context,
          'Đã chép dữ liệu. Dán vào Google Sheets hoặc Excel nhé.',
        );
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return AccountScaffold(
      title: 'Góp ý nhận diện',
      onRefresh: _load,
      children: [
        if (_error != null) ErrorNote(_error!),
        if (s == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (s != null) ...[
          SectionCard(
            title: 'Tổng quan',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line('Tổng số góp ý', '${s.total}'),
                _line('Trong 7 ngày', '${s.last7Days}'),
                _line(
                  'Model đoán đúng (người dùng xác nhận)',
                  '${s.sameAsPrediction}',
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Model hay nhầm',
            child: s.topConfusions.isEmpty
                ? const Text(
                    'Chưa có góp ý nào.',
                    style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                  )
                : Column(
                    children: [
                      for (final p in s.topConfusions)
                        _line(
                          '${p.predictedLabel} → ${p.correct}',
                          '${p.count} lần',
                        ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Từ người dùng muốn thêm (app chưa có)',
            child: s.unknownWords.isEmpty
                ? const Text(
                    'Chưa có từ nào.',
                    style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                  )
                : Column(
                    children: [
                      for (final t in s.unknownWords)
                        _line(t.text, '${t.count} lần'),
                    ],
                  ),
          ),
        ],
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tất cả', style: TextStyle(fontSize: 18)),
              selected: !_unknownOnly,
              onSelected: (_) {
                _unknownOnly = false;
                _load();
              },
            ),
            ChoiceChip(
              label: const Text('Từ chưa có', style: TextStyle(fontSize: 18)),
              selected: _unknownOnly,
              onSelected: (_) {
                _unknownOnly = true;
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading && _items.isEmpty && s != null)
          const Center(child: CircularProgressIndicator()),
        for (final f in _items) _FeedbackTile(f, onDelete: () => _delete(f)),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Đang hiện ${_items.length} / $_total',
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
        const SizedBox(height: 12),
        BusyButton(
          label: 'Chép dữ liệu (CSV)',
          icon: Icons.copy_rounded,
          outlined: true,
          onPressed: _copyCsv,
        ),
      ],
    );
  }

  Widget _line(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(a, style: const TextStyle(fontSize: 18))),
        Text(
          b,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile(this.f, {required this.onDelete});

  final AdminFeedback f;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = (f.predictedProbability * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.predictedLabel} ($p%) → ${f.correctText}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [
                        f.source == 'typed' ? 'gõ tay' : 'chọn trong gợi ý',
                        if (f.correctWordId == null) 'từ chưa có',
                        if (f.isConfirmation) 'model đoán đúng',
                        relativeTime(f.updatedAt, DateTime.now()),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 18,
                        color: Palette.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Xoá góp ý',
                icon: const Icon(Icons.delete_outline_rounded, size: 28),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
