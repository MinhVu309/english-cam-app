import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/pack/pack_store.dart';
import '../../data/pack/pack_updater.dart';
import '../../data/vocab_repository.dart';
import '../../ml/classifier_service.dart';
import '../../services/app_settings.dart';

/// Cập nhật gói từ vựng (và model nếu gói có) từ hosting. Nằm sau cổng phụ huynh.
class PackUpdateScreen extends StatefulWidget {
  const PackUpdateScreen({super.key, this.updater, this.reloadModel});

  /// Cho test thay bằng bản dùng máy chủ giả.
  final PackUpdater? updater;

  /// Mặc định nạp lại [ClassifierService] sau khi cập nhật.
  final Future<void> Function()? reloadModel;

  @override
  State<PackUpdateScreen> createState() => _PackUpdateScreenState();
}

class _PackUpdateScreenState extends State<PackUpdateScreen> {
  late final TextEditingController _url = TextEditingController(
    text: AppSettings.instance.packUrl,
  );
  bool _busy = false;
  bool _changed = false; // đã đổi dữ liệu: về Home phải dựng lại
  double? _progress;
  String? _message;
  bool _isError = false;

  PackStore? get _store => PackStore.instance;

  Future<void> _reloadAll() async {
    await VocabRepository.load();
    await (widget.reloadModel ?? ClassifierService.instance.reload)();
  }

  void _say(String text, {bool error = false}) => setState(() {
    _message = text;
    _isError = error;
  });

  Future<void> _update() async {
    final store = _store;
    if (store == null) {
      _say('Máy này không lưu được gói từ vựng.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final updater = widget.updater ?? PackUpdater(store);
    setState(() {
      _busy = true;
      _progress = null;
      _message = null;
    });
    try {
      final url = _url.text.trim();
      final result = await updater.update(
        url,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _progress = total == 0 ? 0 : done / total);
        },
      );
      await AppSettings.instance.setPackUrl(url);
      if (!result.changed) {
        _say('Đã là bản mới nhất (bản ${result.manifest.version}).');
        return;
      }
      await _reloadAll();
      _changed = true;
      final words = VocabRepository.instance.words.length;
      var text = 'Đã cập nhật lên bản ${result.manifest.version}: $words từ.';
      if (result.manifest.hasModel) {
        text += ClassifierService.instance.source == ModelSource.pack
            ? ' Đã dùng mô hình nhận diện mới.'
            : ' Mô hình mới không dùng được nên app giữ mô hình cũ.';
      }
      final notes = result.manifest.notes;
      if (notes != null) text += '\n$notes';
      _say(text);
    } on PackUpdateException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('Cập nhật thất bại: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Về bản gốc?'),
        content: const Text(
          'Xoá từ vựng và mô hình đã tải, dùng lại bản có sẵn trong app. '
          'Tiến độ học của bé vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ nguyên'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Về bản gốc'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store?.clear();
      await _reloadAll();
      _changed = true;
      _say(
        'Đã quay về từ vựng đóng gói sẵn (${VocabRepository.instance.words.length} từ).',
      );
    } catch (e) {
      _say('Không thực hiện được: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dữ liệu đã đổi thì dựng lại từ Home để mọi màn hình thấy từ vựng mới.
  void _leave() {
    if (_changed) {
      Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = _store?.readInstalled();
    final words = VocabRepository.instance.words.length;
    final current = installed == null
        ? 'Bản đóng gói sẵn · $words từ'
        : 'Bản ${installed.version} · $words từ'
              '${installed.hasModel ? ' · có mô hình mới' : ''}';
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            iconSize: 32,
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _busy ? null : _leave,
          ),
          title: const Text(
            'Cập nhật từ vựng',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _Card(
                child: Text(
                  'Đang dùng: $current',
                  key: const Key('pack-current'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Địa chỉ gói từ vựng',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('pack-url'),
                      controller: _url,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'https://ten-ban.github.io/english-cam-pack/',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        key: const Key('pack-update'),
                        onPressed: _busy ? null : _update,
                        icon: const Icon(Icons.cloud_download_rounded),
                        label: const Text(
                          'Kiểm tra & cập nhật',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _progress),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        key: const Key('pack-message'),
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.4,
                          color: _isError
                              ? Theme.of(context).colorScheme.error
                              : Palette.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (installed != null)
                TextButton(
                  key: const Key('pack-revert'),
                  onPressed: _busy ? null : _revert,
                  child: const Text(
                    'Quay về bản gốc trong app',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Chỉ tải về, không gửi dữ liệu nào đi. Từ vựng đã tải được lưu trong máy '
                  'và dùng được khi không có mạng.',
                  style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}
