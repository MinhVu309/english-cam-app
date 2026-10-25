import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/router.dart';
import '../../../data/vocab_repository.dart';
import '../../../data/vocab_word.dart';
import '../../../ml/classifier_service.dart';
import '../../../services/audio_service.dart';
import '../../../services/game_progress.dart';
import '../../mascot/mascot.dart';
import '../../vocab/word_visual.dart';
import '../badge_dialog.dart';
import 'hunt_logic.dart';

enum _Phase { prompt, checking, success, fail }

/// Game 2: app đọc một từ, bé đi tìm vật thật rồi chụp, model xác nhận.
class HuntGameScreen extends StatefulWidget {
  const HuntGameScreen({super.key, this.random});

  final Random? random;

  @override
  State<HuntGameScreen> createState() => _HuntGameScreenState();
}

class _HuntGameScreenState extends State<HuntGameScreen> {
  late final Random _rng = widget.random ?? Random();
  VocabWord? _targetOrNull;
  VocabWord get _target => _targetOrNull!;
  _Phase _phase = _Phase.prompt;
  String? _photoPath;
  String _failMessage = '';
  int _starsEarned = 0;

  @override
  void initState() {
    super.initState();
    _pickTarget();
  }

  void _pickTarget() {
    _targetOrNull = pickHuntTarget(
      VocabRepository.instance.words,
      _rng,
      previous: _targetOrNull?.id,
    );
    _phase = _Phase.prompt;
    _photoPath = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
  }

  void _speak() => AudioService.instance.playWord(_target);

  Future<void> _capture() async {
    final path = await Navigator.of(context).pushNamed<String>(Routes.camera);
    if (path == null || !mounted) return;
    setState(() {
      _photoPath = path;
      _phase = _Phase.checking;
    });
    try {
      final r = await ClassifierService.instance.classifyFile(path);
      if (!mounted) return;
      if (isHuntSuccess(r, _target.label)) {
        await _succeed(2);
      } else {
        AudioService.instance.playSfx(Sfx.wrong);
        final seen = r.isConfident
            ? VocabRepository.instance.byLabel(r.best.label)
            : null;
        setState(() {
          _failMessage = seen != null
              ? 'Mình thấy giống "${seen.en}" hơn. Thử chụp lại nhé!'
              : 'Mình chưa chắc, thử chụp rõ hơn nhé!';
          _phase = _Phase.fail;
        });
      }
    } catch (e) {
      debugPrint('Hunt classify failed: $e');
      if (!mounted) return;
      setState(() {
        _failMessage = 'Có lỗi rồi, thử lại nhé!';
        _phase = _Phase.fail;
      });
    }
  }

  Future<void> _succeed(int stars) async {
    AudioService.instance.playSfx(Sfx.correct);
    final badges = await GameProgress.instance.recordFound(starsEarned: stars);
    if (!mounted) return;
    setState(() {
      _starsEarned = stars;
      _phase = _Phase.success;
    });
    if (badges.isNotEmpty) showBadgeDialog(context, badges);
  }

  /// Bố mẹ xác nhận khi model nhận sai nhưng bé đã tìm đúng.
  Future<void> _parentConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Bố mẹ xác nhận'),
        content: Text(
          'Bé đã tìm đúng "${_target.en}" (${_target.vi}) chưa?',
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Chưa'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đúng rồi'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _succeed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Tìm vật',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: switch (_phase) {
            _Phase.prompt => _buildPrompt(),
            _Phase.checking => _buildChecking(),
            _Phase.success => _buildSuccess(),
            _Phase.fail => _buildFail(),
          },
        ),
      ),
    );
  }

  Widget _targetCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          WordVisual(word: _target, size: 120),
          const SizedBox(height: 8),
          Text(
            _target.en,
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
          ),
          Text(_target.vi, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          IconButton.filledTonal(
            iconSize: 32,
            constraints: const BoxConstraints.tightFor(width: 64, height: 64),
            tooltip: 'Nghe lại',
            icon: const Icon(Icons.volume_up_rounded),
            onPressed: _speak,
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt() {
    return Column(
      children: [
        const Text(
          'Hãy đi tìm vật này nhé!',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _targetCard(),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.photo_camera_rounded, size: 32),
            label: const Text('Chụp ảnh'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(_pickTarget),
          child: const Text('Đổi vật khác', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }

  Widget _buildChecking() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Để mình xem nhé…', style: TextStyle(fontSize: 24)),
        ],
      ),
    );
  }

  Widget _photo() {
    final path = _photoPath;
    if (path == null) return const SizedBox.shrink();
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: double.infinity,
          child: Image.file(File(path), fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        _photo(),
        const SizedBox(height: 8),
        const Mascot(mood: MascotMood.cheer, size: 88),
        Text(
          'Giỏi quá! Đây là ${_target.en}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        Text(
          '+$_starsEarned ⭐',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(_pickTarget),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Tìm vật khác'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Xong'),
          ),
        ),
      ],
    );
  }

  Widget _buildFail() {
    return Column(
      children: [
        _photo(),
        const SizedBox(height: 8),
        const Mascot(mood: MascotMood.oops, size: 88),
        Text(
          _failMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.photo_camera_rounded),
            label: Text('Chụp lại "${_target.en}"'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _parentConfirm,
            child: const Text('Bố mẹ xác nhận'),
          ),
        ),
        TextButton(
          onPressed: () => setState(_pickTarget),
          child: const Text('Đổi vật khác', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}
