import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

const int kModelInputSize = 224;

/// Đọc ảnh, lấy vùng [crop] (toạ độ chuẩn hoá 0–1, mặc định cả ảnh), resize
/// thẳng về 224×224 (không giữ tỉ lệ) và trả về buffer float32 RGB, pixel giữ
/// nguyên 0–255 (model đã tự Rescaling bên trong).
Future<Float32List> preprocessImageFile(String path, {ui.Rect? crop}) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final src = crop == null
          ? ui.Rect.fromLTWH(0, 0, w, h)
          : ui.Rect.fromLTRB(
              (crop.left * w).clamp(0, w),
              (crop.top * h).clamp(0, h),
              (crop.right * w).clamp(0, w),
              (crop.bottom * h).clamp(0, h),
            );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        src,
        ui.Rect.fromLTWH(
          0,
          0,
          kModelInputSize.toDouble(),
          kModelInputSize.toDouble(),
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final resized = await picture.toImage(kModelInputSize, kModelInputSize);
      picture.dispose();
      try {
        final data = await resized.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) throw StateError('Không đọc được pixel của ảnh');
        return rgbaToFloat32Rgb(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          kModelInputSize,
          kModelInputSize,
        );
      } finally {
        resized.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// RGBA (8 bit/kênh) -> RGB float32, giữ nguyên giá trị 0–255, bỏ kênh alpha.
Float32List rgbaToFloat32Rgb(Uint8List rgba, int width, int height) {
  assert(rgba.length == width * height * 4);
  final out = Float32List(width * height * 3);
  var o = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    out[o++] = rgba[i].toDouble();
    out[o++] = rgba[i + 1].toDouble();
    out[o++] = rgba[i + 2].toDouble();
  }
  return out;
}
