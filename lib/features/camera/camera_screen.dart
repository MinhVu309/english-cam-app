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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final controller = _controller;
    if (lifecycle == AppLifecycleState.inactive) {
      // Giải phóng camera khi app bị che / chuyển nền.
      _controller = null;
      controller?.dispose();
    } else if (lifecycle == AppLifecycleState.resumed &&
        _controller == null &&
        _photo == null) {
      // Người dùng có thể vừa cấp quyền trong Cài đặt.
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() => _state = _CamState.loading);
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
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted || _controller != controller) {
        // Màn hình đã đóng hoặc controller đã bị thay thế trong lúc khởi tạo.
        if (_controller != controller) await controller.dispose();
        return;
      }
      setState(() => _state = _CamState.ready);
    } on CameraException catch (e) {
      _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      setState(() {
        _state = switch (e.code) {
          'CameraAccessDenied' => _CamState.permissionDenied,
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' => _CamState.permissionBlocked,
          _ => _CamState.error,
        };
      });
    } catch (_) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _state = _CamState.error);
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
