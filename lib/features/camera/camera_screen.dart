import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

enum _CamState {
  loading,
  ready,
  permissionDenied,
  permissionBlocked,
  noCamera,
  error,
}

/// Chụp 1 ảnh. Khi bấm "Xong" sẽ pop về đường dẫn file ảnh (String).
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _CamState _state = _CamState.loading;
  XFile? _photo;
  bool _capturing = false;

  /// Đang khởi tạo (kể cả lúc hộp thoại xin quyền hiện ra).
  bool _initializing = false;

  /// Camera đã bị mình giải phóng khi app xuống nền, cần mở lại khi quay về.
  bool _releasedForBackground = false;

  /// Android không báo riêng "chặn hẳn", nên từ chối 2 lần liên tiếp coi như bị chặn.
  int _deniedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release(_controller);
    _controller = null;
    super.dispose();
  }

  /// Hộp thoại xin quyền cũng làm app `inactive`; khi đó không được giải phóng
  /// camera đang khởi tạo dở, nên chỉ xử lý lúc camera đã sẵn sàng.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.inactive) {
      if (_state == _CamState.ready && _controller != null) {
        _release(_controller);
        _controller = null;
        _releasedForBackground = true;
        setState(() => _state = _CamState.loading);
      }
    } else if (lifecycle == AppLifecycleState.resumed) {
      final fromSettings = _state == _CamState.permissionBlocked;
      if (!_initializing &&
          _photo == null &&
          (_releasedForBackground || fromSettings)) {
        _initCamera();
      }
    }
  }

  Future<void> _release(CameraController? controller) async {
    try {
      await controller?.dispose();
    } catch (e) {
      debugPrint('Camera dispose failed: $e');
    }
  }

  Future<void> _initCamera() async {
    if (!mounted || _initializing) return;
    _initializing = true;
    _releasedForBackground = false;
    setState(() => _state = _CamState.loading);
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _state = _CamState.noCamera);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        _controller = null;
        await _release(controller);
        return;
      }
      _deniedCount = 0;
      setState(() => _state = _CamState.ready);
    } on CameraException catch (e) {
      debugPrint('Camera init failed: ${e.code} / ${e.description}');
      _controller = null;
      await _release(controller);
      if (!mounted) return;
      if (e.code == 'CameraAccessDenied') _deniedCount++;
      setState(() {
        _state = switch (e.code) {
          'CameraAccessDenied' when _deniedCount < 2 =>
            _CamState.permissionDenied,
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' => _CamState.permissionBlocked,
          _ => _CamState.error,
        };
      });
    } catch (e, st) {
      debugPrint('Camera init failed: $e\n$st');
      _controller = null;
      await _release(controller);
      if (mounted) setState(() => _state = _CamState.error);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (_capturing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (mounted) setState(() => _photo = file);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chụp chưa được, thử lại nhé!')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_photo != null) return _buildReview(_photo!);
    switch (_state) {
      case _CamState.loading:
        return const Center(child: CircularProgressIndicator());
      case _CamState.ready:
        return _buildPreview();
      case _CamState.permissionDenied:
        return _Message(
          icon: Icons.no_photography_rounded,
          text: 'Mình cần dùng camera để chụp hình nhé!',
          primaryLabel: 'Cho phép',
          onPrimary: _initCamera,
        );
      case _CamState.permissionBlocked:
        return _Message(
          icon: Icons.no_photography_rounded,
          text:
              'Camera đang bị tắt.\nNhờ bố mẹ bật quyền Camera trong '
              'Cài đặt của máy nhé!',
          primaryLabel: 'Thử lại',
          onPrimary: _initCamera,
        );
      case _CamState.noCamera:
        return _Message(
          icon: Icons.videocam_off_rounded,
          text: 'Máy này không tìm thấy camera.',
          primaryLabel: 'Thử lại',
          onPrimary: _initCamera,
        );
      case _CamState.error:
        return _Message(
          icon: Icons.error_outline_rounded,
          text: 'Có lỗi với camera rồi.',
          primaryLabel: 'Thử lại',
          onPrimary: _initCamera,
        );
    }
  }

  Widget _buildPreview() {
    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: ClipRect(child: Center(child: CameraPreview(controller))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Semantics(
            button: true,
            label: 'Chụp ảnh',
            child: GestureDetector(
              onTap: _takePicture,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _capturing ? Colors.white54 : Colors.white,
                  border: Border.all(color: const Color(0xFFFF8A3D), width: 6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview(XFile photo) {
    return Column(
      children: [
        Expanded(child: Image.file(File(photo.path), fit: BoxFit.contain)),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: () => setState(() => _photo = null),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Chụp lại'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(photo.path),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Xong'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String text;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 96, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, color: Colors.white),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Quay lại'),
            ),
          ],
        ),
      ),
    );
  }
}
