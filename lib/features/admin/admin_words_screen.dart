import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../account/account_widgets.dart';

/// Danh sách từ vựng (bản nháp) cho Admin: tìm, lọc theo chủ đề, hiện cả từ đã xoá, thêm/sửa/xoá/khôi phục.
/// Sửa ở đây chỉ đổi bản nháp: app của bé chỉ thấy sau khi xuất bản.
class AdminWordsScreen extends StatefulWidget {
  const AdminWordsScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminWordsScreen> createState() => _AdminWordsScreenState();
}

class _AdminWordsScreenState extends State<AdminWordsScreen> {
  late final AdminService _admin = widget.service ?? AdminService();
  final _search = TextEditingController();
  List<AdminCategory> _categories = [];
  String? _category;
  bool _includeDeleted = false;
  List<AdminWord> _words = [];
  int _total = 0;
  int _page = 1;
  bool _more = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _admin
        .categories()
        .then((c) {
          if (mounted) {
            setState(() => _categories = c.where((x) => !x.isDeleted).toList());
          }
        })
        .catchError(
          (Object _) {},
        ); // lọc theo chủ đề là phụ; danh sách từ vẫn dùng được
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
      final res = await _admin.words(
        search: _search.text.trim(),
        category: _category,
        includeDeleted: _includeDeleted,
        page: append ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        _words = append ? [..._words, ...res.items] : res.items;
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

  Future<void> _open(AdminWord? w) async {
    final changed = await Navigator.of(
      context,
    ).pushNamed<bool>(Routes.adminWordEdit, arguments: w);
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final catName = {for (final c in _categories) c.id: c.vi};
    return AccountScaffold(
      title: 'Từ vựng',
      onRefresh: _load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm từ', style: TextStyle(fontSize: 20)),
      ),
      children: [
        FieldBox(
          controller: _search,
          label: 'Tìm theo từ, nghĩa hoặc mã',
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          suffix: IconButton(
            tooltip: 'Tìm',
            icon: const Icon(Icons.search_rounded),
            onPressed: _load,
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Chủ đề',
            labelStyle: TextStyle(fontSize: 18),
          ),
          style: const TextStyle(fontSize: 20, color: Palette.ink),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Tất cả chủ đề'),
            ),
            for (final c in _categories)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text('${c.emoji ?? ''} ${c.vi}'),
              ),
          ],
          onChanged: (v) {
            _category = v;
            _load();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Hiện cả từ đã xoá',
            style: TextStyle(fontSize: 20),
          ),
          value: _includeDeleted,
          onChanged: (v) {
            _includeDeleted = v;
            _load();
          },
        ),
        if (_error != null) ErrorNote(_error!),
        if (_loading && _words.isEmpty)
          const Center(child: CircularProgressIndicator()),
        if (!_loading && _error == null && _words.isEmpty)
          const Text(
            'Không có từ nào.',
            style: TextStyle(fontSize: 18, color: Palette.inkSoft),
          ),
        for (final w in _words)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: w.isDeleted ? Palette.oops : Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _open(w),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          w.emoji ?? '🔤',
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${w.en} · ${w.vi}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              [
                                catName[w.category] ?? w.category,
                                if (w.label != null) 'nhận diện: ${w.label}',
                                if (w.isDeleted) 'ĐÃ XOÁ',
                              ].join(' · '),
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
        if (_words.isNotEmpty)
          Text(
            'Đang hiện ${_words.length} / $_total',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
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
