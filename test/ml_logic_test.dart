import 'dart:typed_data';
import 'dart:ui';

import 'package:english_cam/ml/classifier_service.dart';
import 'package:english_cam/ml/image_preprocess.dart';
import 'package:english_cam/ml/object_localizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rgbaToFloat32Rgb giữ nguyên 0–255 và bỏ alpha', () {
    final rgba = Uint8List.fromList([255, 0, 10, 99, 1, 2, 3, 255]);
    final out = rgbaToFloat32Rgb(rgba, 2, 1);
    expect(out, [255.0, 0.0, 10.0, 1.0, 2.0, 3.0]);
  });

  test('topK sắp giảm dần và map đúng chỉ số -> nhãn', () {
    final top = topK([0.1, 0.6, 0.05, 0.25], ['a', 'b', 'c', 'd']);
    expect(top.map((p) => p.label), ['b', 'd', 'a']);
    expect(top.first.probability, 0.6);
  });

  test('ngưỡng 0.7: 0.69 chưa chắc, 0.7 thì chắc', () {
    ClassificationResult r(double p) =>
        ClassificationResult(top: [Prediction('x', p)], inferenceMs: 0);
    expect(r(0.69).isConfident, isFalse);
    expect(r(0.70).isConfident, isTrue);
  });

  group('ObjectLocalizer', () {
    test(
      'các ô là hình vuông nằm trong ảnh, có ô cỡ lớn nhất, không quá nhiều',
      () {
        for (final size in [const Size(640, 480), const Size(480, 640)]) {
          final w = ObjectLocalizer.generateWindows(
            size.width.toInt(),
            size.height.toInt(),
          );
          expect(w.length, lessThanOrEqualTo(ObjectLocalizer.maxWindows));
          expect(w.length, greaterThan(10));
          for (final r in w) {
            expect(r.width, r.height);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.top, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(size.width));
            expect(r.bottom, lessThanOrEqualTo(size.height));
          }
          expect(w.any((r) => r.width == 480), isTrue);
        }
      },
    );

    test('ảnh rất dài không tạo quá nhiều ô', () {
      final w = ObjectLocalizer.generateWindows(3000, 200);
      expect(w.length, lessThanOrEqualTo(ObjectLocalizer.maxWindows));
    });

    test('pick trả về khung quanh vùng có xác suất cao', () {
      const image = Size(400, 400);
      final windows = ObjectLocalizer.generateWindows(400, 400);
      // "Vật" nằm ở góc phải dưới: các ô chứa tâm vật có xác suất cao.
      const objectCenter = Offset(300, 300);
      final probs = [
        for (final w in windows) w.contains(objectCenter) ? 0.95 : 0.05,
      ];

      final box = ObjectLocalizer.pick(windows, probs, image)!;
      final r = box.rect;
      expect(r.width, closeTo(r.height, 1e-9)); // vuông trên ảnh vuông
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.bottom, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.contains(const Offset(0.75, 0.75)), isTrue);
      expect(box.probability, 0.95);
    });

    test('pick trả về null khi không ô nào đủ chắc', () {
      final windows = ObjectLocalizer.generateWindows(400, 400);
      final probs = List.filled(windows.length, 0.3);
      expect(
        ObjectLocalizer.pick(windows, probs, const Size(400, 400)),
        isNull,
      );
    });
  });
}
