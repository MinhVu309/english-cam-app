import 'dart:typed_data';

import 'package:english_cam/ml/classifier_service.dart';
import 'package:english_cam/ml/image_preprocess.dart';
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
}
