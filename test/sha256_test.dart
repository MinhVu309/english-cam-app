import 'dart:convert';

import 'package:english_cam/data/pack/sha256.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('khớp vector chuẩn của NIST', () {
    expect(
      Sha256.hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      Sha256.hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      Sha256.hex(
        utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test('độ dài sát ranh giới khối 55/56/64 byte không bị lệch', () {
    // Giá trị tham chiếu tính bằng `shasum -a 256` trên chuỗi 'a' lặp lại.
    const expected = {
      55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
      56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
      64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
    };
    expected.forEach((n, hash) {
      expect(Sha256.hex(List.filled(n, 0x61)), hash, reason: '$n byte');
    });
  });

  test('băm từng đoạn cho cùng kết quả với băm một lần (1 triệu chữ a)', () {
    final h = Sha256();
    final chunk = List.filled(1000, 0x61);
    for (var i = 0; i < 1000; i++) {
      h.add(chunk);
    }
    expect(
      h.close(),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('đóng rồi thì không dùng lại được', () {
    final h = Sha256()..close();
    expect(() => h.add([1]), throwsStateError);
    expect(h.close, throwsStateError);
  });
}
