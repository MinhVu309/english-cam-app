import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

const int kModelInputSize = 224;

/// Giải mã file ảnh (đã áp dụng hướng xoay EXIF nếu có). Người gọi phải `dispose()`.
Future<ui.Image> decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// Lấy vùng [src] (đơn vị pixel của [image]; mặc định cả ảnh), resize thẳng về
/// 224×224 (không giữ tỉ lệ) và trả về buffer float32 RGB, pixel giữ nguyên
/// 0–255 (model đã tự Rescaling bên trong).
Future<Float32List> imageRegionToFloat32(ui.Image image, {ui.Rect? src}) async {
  final from =
      src ??
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    from,
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
    final data = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Không đọc được pixel của ảnh');
    return rgbaToFloat32Rgb(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      kModelInputSize,
      kModelInputSize,
    );
  } finally {
    resized.dispose();
  }
}

/// Đọc cả file ảnh và tiền xử lý cho model.
Future<Float32List> preprocessImageFile(String path) async {
  final image = await decodeImageFile(path);
  try {
    return await imageRegionToFloat32(image);
  } finally {
    image.dispose();
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
