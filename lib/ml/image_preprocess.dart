import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

const int kModelInputSize = 224;

/// Đọc ảnh, resize thẳng về 224×224 (không crop giữ tỉ lệ) và trả về buffer
/// float32 RGB, pixel giữ nguyên 0–255 (model đã tự Rescaling bên trong).
Future<Float32List> preprocessImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: kModelInputSize,
    targetHeight: kModelInputSize,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Không đọc được pixel của ảnh');
      return rgbaToFloat32Rgb(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
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
