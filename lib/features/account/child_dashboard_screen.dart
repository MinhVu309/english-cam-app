import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/account/account_models.dart';
import '../../data/account/dashboard_models.dart';
import '../../data/vocab_repository.dart';
import '../../services/audio_service.dart';
import '../../services/auth_service.dart';
import 'account_widgets.dart';
import 'dashboard_charts.dart';

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Nhãn trục x: thứ trong tuần khi xem 7 ngày, ngày/tháng khi xem nhiều hơn.
String dayLabel(DateTime d, int days) =>
    days <= 7 ? _weekdays[d.weekday - 1] : '${d.day}/${d.month}';

/// Dashboard cho phụ huynh: bé đã học bao nhiêu, học đều không, từ nào còn yếu, hôm nay dùng bao lâu.
class ChildDashboardScreen extends StatefulWidget {
  const ChildDashboardScreen({super.key, required this.child});

  final ChildProfile child;

  @override
  State<ChildDashboardScreen> createState() => _ChildDashboardScreenState();
}

class _ChildDashboardScreenState extends State<ChildDashboardScreen> {
  ChildDashboard? _data;
  String? _error;
  bool _loading = true;
  int _days = 7;

  AuthService get _auth => AuthService.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Phiên phụ huynh hết hạn giữa chừng: về trang chủ (AuthService đã báo qua thông báo).
  void _onAuthChanged() {
    if (!_auth.isParentSignedIn && mounted) {
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final days = _days;
    try {
      final d = await _auth.loadDashboard(widget.child.id, days);
      if (mounted && days == _days) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  Future<void> _copyCsv(String kind) async {
    try {
      final csv = await _auth.exportCsv(
        widget.child.id,
        kind: kind,
        days: _days < 30 ? 30 : _days,
      );
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

  void _play(WeakWord w) {
    try {
      final word = VocabRepository.instance.byId(w.wordId);
      if (word != null) {
        AudioService.instance.playWord(word);
      }
    } on StateError {
      // từ vựng chưa nạp: không phát được, bỏ qua
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return AccountScaffold(
      title: 'Tiến độ của ${widget.child.nickname}',
      onRefresh: _load,
      children: [
        Row(
          children: [
            AvatarBubble(avatarKey: widget.child.avatarKey, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.child.nickname,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 ngày')),
            ButtonSegment(value: 30, label: Text('30 ngày')),
          ],
          selected: {_days},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setDays(s.first),
        ),
        const SizedBox(height: 14),
        if (_error != null) ...[
          ErrorNote(_error!),
          BusyButton(label: 'Thử lại', onPressed: _load),
        ] else if (d == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          _Summary(d),
          _ActivityCharts(d),
          _Accuracy(d),
          _Categories(d),
          _WeakWords(d, onPlay: _play),
          _Badges(d),
          _Recent(d),
          SectionCard(
            title: 'Xuất dữ liệu',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chép dữ liệu dạng bảng (CSV) để dán vào Google Sheets hoặc Excel.',
                  style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                ),
                const SizedBox(height: 12),
                BusyButton(
                  label: 'Chép dữ liệu theo ngày',
                  icon: Icons.calendar_month_rounded,
                  outlined: true,
                  onPressed: () => _copyCsv('daily'),
                ),
                const SizedBox(height: 10),
                BusyButton(
                  label: 'Chép dữ liệu theo từ',
                  icon: Icons.abc_rounded,
                  outlined: true,
                  onPressed: () => _copyCsv('words'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    final t = d.totals;
    final limit = d.dailyLimitMinutes;
    final over = d.overLimitToday;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Tile(
                  child: Column(
                    children: [
                      ProgressRing(
                        value: t.totalWords == 0
                            ? 0
                            : t.learnedWords / t.totalWords,
                        semanticLabel:
                            'Đã học ${t.learnedWords} trên ${t.totalWords} từ',
                        child: Text(
                          '${t.learnedWords}/${t.totalWords}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('từ đã học', style: TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tile(
                  child: Column(
                    children: [
                      Text(
                        '⭐ ${t.stars}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text('sao', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 6),
                      Text(
                        '${t.rounds} ván · ${t.perfectRounds} hoàn hảo',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Palette.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Tile(
                  child: Column(
                    children: [
                      Text(
                        '🔥 ${t.currentStreak}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'ngày liên tiếp',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Kỷ lục ${t.bestStreak} ngày',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Palette.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tile(
                  child: Column(
                    children: [
                      const Text(
                        'Hôm nay',
                        style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                      ),
                      Text(
                        formatDuration(d.today.seconds),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: over ? Colors.red.shade800 : Palette.ink,
                        ),
                      ),
                      if (limit != null) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (d.today.seconds / (limit * 60)).clamp(
                            0.0,
                            1.0,
                          ),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                          color: over ? Colors.red.shade700 : Palette.teal,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          over
                              ? 'Vượt giới hạn $limit phút'
                              : 'Giới hạn $limit phút',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: over ? Colors.red.shade800 : Palette.inkSoft,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${d.today.wordsLearned}/${d.dailyWordGoal} từ mới${d.today.goalMet ? ' ✅' : ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Center(child: child),
  );
}

class _ActivityCharts extends StatelessWidget {
  const _ActivityCharts(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    final labels = [for (final x in d.daysData) dayLabel(x.date, d.days)];
    final minutes = [for (final x in d.daysData) x.minutes];
    final words = [for (final x in d.daysData) x.wordsLearned.toDouble()];
    final totalMinutes = minutes.fold<double>(0, (a, b) => a + b).round();
    final totalWords = d.daysData.fold<int>(0, (a, b) => a + b.wordsLearned);
    final activeDays = d.daysData
        .where(
          (x) =>
              x.seconds > 0 ||
              x.wordsLearned > 0 ||
              x.rounds > 0 ||
              x.scans > 0,
        )
        .length;
    return Column(
      children: [
        SectionCard(
          title: 'Thời gian học (phút mỗi ngày)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tổng ${d.days} ngày: $totalMinutes phút · học $activeDays/${d.days} ngày',
                style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
              const SizedBox(height: 8),
              BarChart(
                values: minutes,
                labels: labels,
                color: Palette.orange,
                semanticLabel:
                    'Biểu đồ số phút học mỗi ngày trong ${d.days} ngày, tổng $totalMinutes phút',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Từ mới mỗi ngày',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tổng $totalWords từ mới trong ${d.days} ngày',
                style: const TextStyle(fontSize: 18, color: Palette.inkSoft),
              ),
              const SizedBox(height: 8),
              BarChart(
                values: words,
                labels: labels,
                color: Palette.teal,
                semanticLabel:
                    'Biểu đồ số từ mới mỗi ngày trong ${d.days} ngày, tổng $totalWords từ',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Accuracy extends StatelessWidget {
  const _Accuracy(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    final a = d.totals.accuracyPercent;
    return SectionCard(
      title: 'Độ chính xác',
      child: a == null
          ? const Text(
              'Chưa có ván "Nghe & chọn hình" nào trong khoảng này.',
              style: TextStyle(fontSize: 18, color: Palette.inkSoft),
            )
          : Row(
              children: [
                Text(
                  '$a%',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'số câu bé chọn đúng ngay lần đầu',
                    style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Theo chủ đề',
      child: Column(
        children: [
          for (final c in d.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      c.emoji ?? '•',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      c.vi,
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Semantics(
                      label: '${c.vi}: ${c.learned} trên ${c.total} từ',
                      child: LinearProgressIndicator(
                        value: c.total == 0 ? 0 : c.learned / c.total,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(8),
                        color: Palette.teal,
                        backgroundColor: Palette.teal.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${c.learned}/${c.total}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WeakWords extends StatelessWidget {
  const _WeakWords(this.d, {required this.onPlay});

  final ChildDashboard d;
  final void Function(WeakWord) onPlay;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Từ cần ôn thêm',
      child: d.weakWords.isEmpty
          ? const Text(
              'Chưa có từ nào bé hay nhầm. Cứ chơi thêm nhé!',
              style: TextStyle(fontSize: 18, color: Palette.inkSoft),
            )
          : Column(
              children: [
                for (final w in d.weakWords)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      w.emoji ?? '📝',
                      style: const TextStyle(fontSize: 32),
                    ),
                    title: Text(
                      '${w.en} · ${w.vi}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Đúng ngay lần đầu ${w.accuracyPercent}% (${w.total - w.wrong}/${w.total} lần)',
                      style: const TextStyle(fontSize: 18),
                    ),
                    trailing: IconButton(
                      iconSize: 30,
                      tooltip: 'Nghe "${w.en}"',
                      icon: const Icon(Icons.volume_up_rounded),
                      onPressed: () => onPlay(w),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Huy hiệu (${d.badgesUnlocked}/${d.badgesTotal})',
      child: d.recentBadges.isEmpty
          ? const Text(
              'Chưa có huy hiệu nào.',
              style: TextStyle(fontSize: 18, color: Palette.inkSoft),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in d.recentBadges)
                  Tooltip(
                    message: b.description,
                    child: Chip(
                      avatar: Text(
                        b.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                      label: Text(b.name, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent(this.d);

  final ChildDashboard d;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SectionCard(
      title: 'Hoạt động gần đây',
      child: d.recent.isEmpty
          ? const Text(
              'Chưa có hoạt động nào.',
              style: TextStyle(fontSize: 18, color: Palette.inkSoft),
            )
          : Column(
              children: [
                for (final r in d.recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.isHunt ? Icons.search_rounded : Icons.hearing_rounded,
                      size: 30,
                    ),
                    title: Text(
                      r.isHunt
                          ? 'Tìm vật: ${r.wordEn ?? 'một vật'}${r.wordVi != null ? ' (${r.wordVi})' : ''}'
                          : 'Nghe & chọn hình: ${r.correct}/${r.questions} câu',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '⭐ ${r.stars} · ${relativeTime(r.at, now)}',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),
    );
  }
}
