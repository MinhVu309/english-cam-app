import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:english_cam/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// Không gọi TestWidgetsFlutterBinding: binding sẽ chặn HttpClient thật, còn nhóm test cuối cần máy chủ HTTP cục bộ.
ApiClient _client(
  FakeServer s, {
  bool insecure = false,
  String base = 'https://api.test',
}) => ApiClient(baseUrl: base, transport: s.call, allowInsecure: insecure);

void main() {
  group('Gắn token và xử lý 401', () {
    test('chỉ gắn Bearer khi loại auth có token', () async {
      final s = FakeServer()..on('GET /api/x', 200, {'ok': true});
      final c = _client(s)
        ..tokenFor = (k) => switch (k) {
          ApiAuth.parent => 'P',
          ApiAuth.child => 'C',
          ApiAuth.none => 'KHÔNG ĐƯỢC DÙNG',
        };
      await c.get('/api/x');
      await c.get('/api/x', auth: ApiAuth.parent);
      await c.get('/api/x', auth: ApiAuth.child);
      expect(s.calls[0].headers.containsKey('Authorization'), isFalse);
      expect(s.calls[1].headers['Authorization'], 'Bearer P');
      expect(s.calls[2].headers['Authorization'], 'Bearer C');
    });

    test('401 có token → báo onUnauthorized đúng loại', () async {
      final s = FakeServer()..on('GET /api/x', 401);
      final seen = <ApiAuth>[];
      final c = _client(s)
        ..tokenFor = ((_) => 'T')
        ..onUnauthorized = seen.add;
      await expectLater(
        c.get('/api/x', auth: ApiAuth.child),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      expect(seen, [ApiAuth.child]);
    });

    test('401 KHÔNG có token (sai mật khẩu) → không coi là hết phiên', () async {
      final s = FakeServer()..on('POST /api/auth/login', 401, {'message': 'Sai tài khoản hoặc mật khẩu'});
      var fired = false;
      final c = _client(s)..onUnauthorized = (_) => fired = true;
      await expectLater(
        c.post('/api/auth/login', body: {'a': 1}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sai tài khoản hoặc mật khẩu')),
      );
      expect(fired, isFalse);
    });

    test('token ghi đè dùng cho đăng xuất sau khi phiên đã xoá', () async {
      final s = FakeServer()..on('POST /api/auth/logout', 204);
      final c = _client(s)..tokenFor = (_) => null;
      await c.post('/api/auth/logout', token: 'CŨ');
      expect(s.calls.single.headers['Authorization'], 'Bearer CŨ');
    });
  });

  group('Đọc phản hồi', () {
    test('thân rỗng (204) → null; JSON → đối tượng', () async {
      final s = FakeServer()
        ..on('DELETE /api/a', 204)
        ..on('GET /api/b', 200, {'n': 1});
      final c = _client(s);
      expect(await c.delete('/api/a'), isNull);
      expect(await c.get('/api/b'), {'n': 1});
    });

    test('gửi body dạng JSON', () async {
      final s = FakeServer()..on('POST /api/a', 200, {});
      await _client(s).post('/api/a', body: {'tên': 'Bi'});
      expect(s.calls.single.body, jsonEncode({'tên': 'Bi'}));
      expect(s.calls.single.method, 'POST');
    });

    test('2xx nhưng không phải JSON → báo lỗi dễ hiểu', () async {
      final c = ApiClient(
        baseUrl: 'https://api.test',
        transport: (_) async => const HttpResponseData(200, '<html>'),
      );
      await expectLater(c.get('/api/a'), throwsA(isA<ApiException>()));
    });
  });

  group('Tải văn bản (CSV)', () {
    test('trả nguyên văn, không giải mã JSON, bỏ BOM đầu file, gắn token', () async {
      final s = FakeServer()
        ..handle('GET /api/x.csv', (_) => const HttpResponseData(200, '\uFEFFa,b\r\n1,"{không phải json}"\r\n'));
      final c = _client(s)..tokenFor = ((_) => 'P');
      expect(await c.getText('/api/x.csv', auth: ApiAuth.parent), 'a,b\r\n1,"{không phải json}"\r\n');
      expect(s.calls.single.headers['Authorization'], 'Bearer P');
    });

    test('lỗi vẫn thành ApiException tiếng Việt và 401 vẫn báo hết phiên', () async {
      final s = FakeServer()
        ..on('GET /api/x.csv', 404)
        ..on('GET /api/y.csv', 401);
      var fired = false;
      final c = _client(s)
        ..tokenFor = ((_) => 'P')
        ..onUnauthorized = (_) => fired = true;
      await expectLater(c.getText('/api/x.csv', auth: ApiAuth.parent), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
      await expectLater(c.getText('/api/y.csv', auth: ApiAuth.parent), throwsA(isA<ApiException>()));
      expect(fired, isTrue);
    });
  });

  group('Thông báo lỗi tiếng Việt', () {
    Future<String> messageOf(int status, Object? body) async {
      final s = FakeServer()..on('POST /api/a', status, body);
      try {
        await _client(s).post('/api/a');
      } on ApiException catch (e) {
        return e.message;
      }
      fail('lẽ ra phải ném ApiException');
    }

    test('{message}', () async {
      expect(await messageOf(403, {'message': 'Tài khoản đã bị khoá'}), 'Tài khoản đã bị khoá');
    });

    test('{errors: [..]} của Identity được dịch', () async {
      expect(
        await messageOf(400, {
          'errors': [
            "Email 'a@b.com' is already taken.",
            "Passwords must have at least one digit ('0'-'9').",
          ],
        }),
        'Email này đã được đăng ký.\nMật khẩu cần ít nhất một chữ số.',
      );
    });

    test('{errors: {Field: [..]}} của validation theo tên trường', () async {
      expect(
        await messageOf(400, {
          'errors': {
            'Password': ["The field Password must be a string or array type with a minimum length of '8'."],
            'FullName': ['whatever'],
          },
        }),
        'Mật khẩu tối thiểu 8 ký tự.\nHọ tên cần từ 2 đến 100 ký tự.',
      );
    });

    test('không có thân → thông báo theo mã', () async {
      expect(await messageOf(423, null), contains('quá nhiều lần'));
      expect(await messageOf(429, null), contains('quá nhiều lần'));
      expect(await messageOf(500, null), contains('HTTP 500'));
      expect(await messageOf(404, null), contains('Không tìm thấy'));
    });
  });

  group('Lỗi mạng', () {
    Future<ApiException> failWith(Object error) async {
      final c = ApiClient(
        baseUrl: 'https://api.test',
        transport: (_) async => throw error,
      );
      try {
        await c.get('/api/a');
      } on ApiException catch (e) {
        return e;
      }
      fail('lẽ ra phải ném ApiException');
    }

    test('mất mạng / quá hạn / TLS đều thành thông báo, status = null', () async {
      final socket = await failWith(const SocketException('x'));
      expect(socket.isNetwork, isTrue);
      expect(socket.message, contains('Không kết nối được'));
      expect((await failWith(TimeoutException('x'))).message, contains('quá chậm'));
      expect((await failWith(const HandshakeException('x'))).message, contains('an toàn'));
    });
  });

  group('Địa chỉ máy chủ', () {
    test('bản release (allowInsecure=false) chặn http', () async {
      final s = FakeServer()..on('GET /api/a', 200, {});
      await expectLater(
        _client(s, base: 'http://api.test').get('/api/a'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('https'))),
      );
      expect(s.calls, isEmpty);
    });

    test('bản debug cho phép http; dấu / thừa ở cuối được bỏ', () async {
      final s = FakeServer()..on('GET /api/a', 200, {'ok': 1});
      final c = _client(s, insecure: true, base: 'http://10.0.2.2:5080/');
      expect(await c.get('/api/a'), {'ok': 1});
      expect(s.calls.single.url.toString(), 'http://10.0.2.2:5080/api/a');
    });

    test('scheme lạ bị chặn', () async {
      await expectLater(
        _client(FakeServer(), insecure: true, base: 'ftp://x').get('/a'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ioTransport với máy chủ HTTP thật cục bộ', () {
    late HttpServer server;
    final seen = <Map<String, String?>>[];

    setUp(() async {
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        seen.add({
          'method': req.method,
          'path': req.uri.path,
          'auth': req.headers.value('authorization'),
          'type': req.headers.contentType?.mimeType,
          'body': body,
        });
        req.response
          ..statusCode = req.uri.path == '/api/lỗi' ? 400 : 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true, 'tiếng': 'Việt'}));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('gửi đúng method, header, body UTF-8 và đọc được tiếng Việt', () async {
      final c = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}', allowInsecure: true)
        ..tokenFor = (_) => 'JWT';
      final res = await c.post('/api/echo', body: {'tên': 'Bé Bi'}, auth: ApiAuth.parent);
      expect(res, {'ok': true, 'tiếng': 'Việt'});
      expect(seen.single, {
        'method': 'POST',
        'path': '/api/echo',
        'auth': 'Bearer JWT',
        'type': 'application/json',
        'body': jsonEncode({'tên': 'Bé Bi'}),
      });
    });

    test('máy chủ không chạy → lỗi mạng dễ hiểu, không crash', () async {
      final port = server.port;
      await server.close(force: true);
      final c = ApiClient(baseUrl: 'http://127.0.0.1:$port', allowInsecure: true);
      await expectLater(
        c.get('/api/a'),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });
  });
}
