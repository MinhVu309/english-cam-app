import 'dart:math' as math;
import 'dart:ui';

import 'classifier_service.dart';
import 'image_preprocess.dart';

/// Khung vuông quanh vật, toạ độ chuẩn hoá (0–1) trên ảnh.
class DetectionBox {
  const DetectionBox(this.rect, this.probability);

  final Rect rect;
  final double probability;
}

/// Ước lượng vị trí vật bằng model phân loại sẵn có: cho model xem nhiều ô
/// vuông ở vài cỡ khác nhau, gộp xác suất của vật đó thành bản đồ nhiệt rồi lấy
/// vùng nóng nhất làm khung vuông. Đây là ước lượng, không phải bộ phát hiện
/// vật thật nên khung có thể lệch hoặc rộng hơn vật.
class ObjectLocalizer {
  ObjectLocalizer(this._classifier);

  static final ObjectLocalizer instance = ObjectLocalizer(
    ClassifierService.instance,
  );

  final ClassifierService _classifier;

  /// Cạnh ô vuông = tỉ lệ × cạnh ngắn của ảnh.
  /// Ba cỡ (~24 ô/ảnh): bộ 4 cỡ cho khung gần giống nhưng chậm gấp đôi trên máy yếu
  /// (suy luận ~45–65 ms/ô trên Snapdragon 685).
  static const List<double> scales = [1.0, 0.7, 0.5];

  /// Bước trượt = tỉ lệ × cạnh ô.
  static const double stride = 0.5;

  /// Số ô tối đa mỗi ảnh (ảnh rất dài sẽ tăng bước trượt để không quá chậm).
  static const int maxWindows = 40;

  /// Xác suất cao nhất phải đạt ngưỡng này mới vẽ khung.
  static const double minProbability = 0.5;

  /// Bản đồ nhiệt: số ô lưới mỗi chiều, độ sắc (mũ của xác suất), ngưỡng vùng
  /// nóng so với đỉnh, và phần đệm thêm quanh khung.
  static const int grid = 48;
  static const double gamma = 2;
  static const double heatThreshold = 0.6;
  static const double padding = 0.04;

  /// Các ô vuông (đơn vị pixel) phủ ảnh [width]×[height].
  static List<Rect> generateWindows(
    int width,
    int height, {
    List<double> scales = ObjectLocalizer.scales,
    double stride = ObjectLocalizer.stride,
  }) {
    var s = stride;
    while (true) {
      final out = _windows(width, height, scales, s);
      if (out.length <= maxWindows || s > 4) return out;
      s *= 1.3;
    }
  }

  static List<Rect> _windows(
    int width,
    int height,
    List<double> scales,
    double stride,
  ) {
    final shortest = width < height ? width : height;
    final out = <Rect>[];
    final seen = <String>{};
    for (final scale in scales) {
      final side = (shortest * scale).roundToDouble();
      final step = (side * stride).clamp(1, double.infinity).toDouble();
      for (final top in _positions(height.toDouble(), side, step)) {
        for (final left in _positions(width.toDouble(), side, step)) {
          final r = Rect.fromLTWH(left, top, side, side);
          if (seen.add('${r.left}/${r.top}/${r.width}')) out.add(r);
        }
      }
    }
    return out;
  }

  static List<double> _positions(double length, double side, double step) {
    final last = length - side;
    if (last <= 0) return const [0];
    final out = <double>[];
    for (var p = 0.0; p < last; p += step) {
      out.add(p.roundToDouble());
    }
    out.add(last);
    return out;
  }

  /// Gộp xác suất [probs] của từng ô [windows] thành bản đồ nhiệt rồi trả về
  /// khung vuông quanh vùng nóng. Null nếu không ô nào đạt [minProbability].
  static DetectionBox? pick(
    List<Rect> windows,
    List<double> probs,
    Size image,
  ) {
    assert(windows.length == probs.length);
    var best = 0.0;
    for (final p in probs) {
      if (p > best) best = p;
    }
    if (best < minProbability) return null;

    final sum = List<double>.filled(grid * grid, 0);
    final count = List<int>.filled(grid * grid, 0);
    for (var i = 0; i < windows.length; i++) {
      final w = windows[i];
      final x0 = (w.left / image.width * grid).floor().clamp(0, grid - 1);
      final x1 = (w.right / image.width * grid).ceil().clamp(x0 + 1, grid);
      final y0 = (w.top / image.height * grid).floor().clamp(0, grid - 1);
      final y1 = (w.bottom / image.height * grid).ceil().clamp(y0 + 1, grid);
      final v = math.pow(probs[i], gamma).toDouble();
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          sum[y * grid + x] += v;
          count[y * grid + x]++;
        }
      }
    }
    final heat = List<double>.generate(
      grid * grid,
      (c) => count[c] == 0 ? 0 : sum[c] / count[c],
    );
    var peak = 0;
    for (var c = 1; c < heat.length; c++) {
      if (heat[c] > heat[peak]) peak = c;
    }
    final limit = heat[peak] * heatThreshold;

    // Vùng nóng liên thông chứa đỉnh.
    final seen = List<bool>.filled(grid * grid, false);
    final stack = <int>[peak];
    seen[peak] = true;
    var minX = grid, maxX = 0, minY = grid, maxY = 0;
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final x = c % grid, y = c ~/ grid;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (final n in [
        if (x > 0) c - 1,
        if (x < grid - 1) c + 1,
        if (y > 0) c - grid,
        if (y < grid - 1) c + grid,
      ]) {
        if (!seen[n] && heat[n] >= limit) {
          seen[n] = true;
          stack.add(n);
        }
      }
    }

    final left = minX / grid * image.width;
    final right = (maxX + 1) / grid * image.width;
    final top = minY / grid * image.height;
    final bottom = (maxY + 1) / grid * image.height;
    final shortest = math.min(image.width, image.height);
    final side = math.min(
      math.max(right - left, bottom - top) * (1 + 2 * padding),
      shortest,
    );
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;
    final l = (cx - side / 2).clamp(0, image.width - side).toDouble();
    final t = (cy - side / 2).clamp(0, image.height - side).toDouble();
    return DetectionBox(
      Rect.fromLTWH(
        l / image.width,
        t / image.height,
        side / image.width,
        side / image.height,
      ),
      best,
    );
  }

  /// Tìm khung quanh vật có nhãn [label]. [isCancelled] được hỏi giữa các ô để
  /// dừng sớm (vd. người dùng đã rời màn hình).
  Future<DetectionBox?> localize(
    String path,
    String label, {
    bool Function()? isCancelled,
  }) async {
    await _classifier.init();
    final index = _classifier.labels.indexOf(label);
    if (index < 0) return null;

    final image = await decodeImageFile(path);
    try {
      final windows = generateWindows(image.width, image.height);
      final probs = <double>[];
      for (final w in windows) {
        if (isCancelled?.call() ?? false) return null;
        final input = await imageRegionToFloat32(image, src: w);
        final all = await _classifier.probabilities(input);
        probs.add(all[index]);
      }
      return pick(
        windows,
        probs,
        Size(image.width.toDouble(), image.height.toDouble()),
      );
    } finally {
      image.dispose();
    }
  }
}
