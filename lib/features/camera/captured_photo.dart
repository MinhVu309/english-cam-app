import 'dart:ui';

/// Ảnh vừa chụp + vùng khung ngắm (toạ độ chuẩn hoá 0–1 trên ảnh).
class CapturedPhoto {
  const CapturedPhoto(this.path, this.crop);

  final String path;
  final Rect crop;
}
