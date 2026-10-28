import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../data/pack/pack_manifest.dart';
import '../data/pack/pack_store.dart';
import 'image_preprocess.dart';

const String kModelAsset = 'assets/ml/model.tflite';
const String kLabelsAsset = 'assets/ml/labels.txt';

/// Chỉ hiện kết quả khi xác suất cao nhất >= ngưỡng này (model không có lớp `none`).
const double kConfidenceThreshold = 0.7;

/// Số luồng CPU cho TFLite. Đo trên Xiaomi 23021RAAEG: 1 luồng 65 ms, 2 luồng 44 ms,
/// 4 luồng 49 ms mỗi lần suy luận, nên dùng 2.
const int kInterpreterThreads = 2;

class Prediction {
  const Prediction(this.label, this.probability);

  /// Nhãn đúng như trong labels.txt (vd. `teddy_bear`).
  final String label;
  final double probability;
}

class ClassificationResult {
  const ClassificationResult({
    required this.top,
    required this.inferenceMs,
    this.threshold = kConfidenceThreshold,
  });

  /// Top-k, xác suất giảm dần.
  final List<Prediction> top;

  /// Thời gian tiền xử lý + suy luận.
  final int inferenceMs;
  final double threshold;

  Prediction get best => top.first;
  bool get isConfident => best.probability >= threshold;
}

/// Lấy top-[k] từ vector xác suất; chỉ số i ↔ labels[i].
List<Prediction> topK(List<double> probs, List<String> labels, {int k = 3}) {
  assert(probs.length == labels.length);
  final idx = List<int>.generate(probs.length, (i) => i)
    ..sort((a, b) => probs[b].compareTo(probs[a]));
  return [for (final i in idx.take(k)) Prediction(labels[i], probs[i])];
}

enum ModelSource { bundled, pack }

/// Singleton: nạp model một lần, suy luận chạy trong isolate riêng.
class ClassifierService {
  ClassifierService._();
  static final ClassifierService instance = ClassifierService._();

  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  List<String> _labels = const [];
  Future<void>? _initFuture;

  // IsolateInterpreter bỏ qua lệnh gọi chồng nhau, nên xếp hàng tuần tự.
  Future<void> _queue = Future.value();

  List<String> get labels => _labels;

  Future<void> init() => _initFuture ??= _load().catchError((Object e) {
    _initFuture = null; // cho phép thử lại
    throw e;
  });

  /// Model đang dùng: đóng gói sẵn hay từ gói từ vựng đã tải.
  ModelSource _source = ModelSource.bundled;
  ModelSource get source => _source;

  /// Ưu tiên model của gói đã tải; không đúng hợp đồng hoặc không nạp được thì
  /// dùng model đóng gói sẵn, nên gói hỏng không làm app mất khả năng nhận diện.
  Future<void> _load() async {
    final store = PackStore.instance;
    final modelFile = store?.fileFor(kPackModelFile);
    final labelsFile = store?.fileFor(kPackLabelsFile);
    if (modelFile != null && labelsFile != null) {
      try {
        await _adopt(
          _parseLabels(await labelsFile.readAsString()),
          Interpreter.fromFile(modelFile, options: _options()),
        );
        _source = ModelSource.pack;
        return;
      } catch (e) {
        debugPrint('Pack model rejected, using bundled: $e');
      }
    }
    final labels = _parseLabels(await rootBundle.loadString(kLabelsAsset));
    final interpreter = await Interpreter.fromAsset(
      kModelAsset,
      options: _options(),
    );
    await _adopt(labels, interpreter);
    _source = ModelSource.bundled;
  }

  static InterpreterOptions _options() =>
      InterpreterOptions()..threads = kInterpreterThreads;

  static List<String> _parseLabels(String raw) =>
      raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  /// Kiểm tra hợp đồng model (input 1×224×224×3 float32, output 1×N float32 với
  /// N = số nhãn) rồi mới nhận; sai thì đóng interpreter và ném lỗi.
  Future<void> _adopt(List<String> labels, Interpreter interpreter) async {
    final inTensor = interpreter.getInputTensor(0);
    final outTensor = interpreter.getOutputTensor(0);
    final inShape = inTensor.shape;
    final outShape = outTensor.shape;
    final ok =
        inShape.length == 4 &&
        inShape[0] == 1 &&
        inShape[1] == kModelInputSize &&
        inShape[2] == kModelInputSize &&
        inShape[3] == 3 &&
        inTensor.type == TensorType.float32 &&
        outShape.length == 2 &&
        outShape[0] == 1 &&
        outShape[1] == labels.length &&
        outTensor.type == TensorType.float32;
    if (!ok) {
      interpreter.close();
      throw StateError(
        'Model không khớp hợp đồng: input $inShape ${inTensor.type}, '
        'output $outShape ${outTensor.type}, ${labels.length} nhãn',
      );
    }
    _labels = labels;
    _interpreter = interpreter;
    _isolate = await IsolateInterpreter.create(address: interpreter.address);
  }

  /// Nạp lại sau khi gói từ vựng được cập nhật hoặc xoá.
  Future<void> reload() async {
    await dispose();
    _labels = const [];
    await init();
  }

  Future<ClassificationResult> classifyFile(String path) async {
    final sw = Stopwatch()..start();
    final input = await preprocessImageFile(path);
    return classifyPixels(input, stopwatch: sw);
  }

  /// [input]: float32 RGB 224×224×3, giá trị 0–255.
  Future<ClassificationResult> classifyPixels(
    Float32List input, {
    Stopwatch? stopwatch,
  }) async {
    final sw = stopwatch ?? (Stopwatch()..start());
    final probs = await probabilities(input);
    sw.stop();
    return ClassificationResult(
      top: topK(probs, _labels),
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  /// Xác suất của mọi lớp (chỉ số i ↔ dòng i của labels.txt).
  Future<Float32List> probabilities(Float32List input) async {
    await init();
    final output = Float32List(_labels.length);

    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      await _isolate!.run(input.buffer, output.buffer);
    } finally {
      done.complete();
    }
    return output;
  }

  Future<void> dispose() async {
    await _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
    _initFuture = null;
  }
}
