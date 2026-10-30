import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_config.dart';

/// Loại token gắn vào request: token phụ huynh/admin, token của bé, hoặc không gắn (đăng nhập, từ vựng công khai).
enum ApiAuth { none, parent, child }

/// Lỗi gọi API đã được đổi thành thông báo tiếng Việt để hiện thẳng cho người dùng.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;

  /// null nghĩa là không tới được máy chủ (mất mạng, quá hạn, lỗi TLS).
  final int? status;

  bool get isNetwork => status == null;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status, $message)';
}

class HttpRequestData {
  const HttpRequestData(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
}

class HttpResponseData {
  const HttpResponseData(this.status, this.body);

  final int status;
  final String body;
}

/// Lớp vận chuyển tách riêng để test thay bằng bản giả (không cần mạng/máy chủ).
typedef Transport = Future<HttpResponseData> Function(HttpRequestData request);

/// Vận chuyển thật bằng dart:io HttpClient (cùng cách `PackUpdater` đang dùng, không thêm package HTTP).
Transport ioTransport({HttpClient Function()? clientFactory}) {
  return (r) async {
    final client = (clientFactory ?? HttpClient.new)()
      ..connectionTimeout = ApiConfig.connectTimeout;
    try {
      final req = await client.openUrl(r.method, r.url);
      r.headers.forEach(req.headers.set);
      if (r.body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(r.body!));
      }
      final res = await req.close().timeout(ApiConfig.idleTimeout);
      final text = await utf8.decodeStream(res).timeout(ApiConfig.idleTimeout);
      return HttpResponseData(res.statusCode, text);
    } finally {
      client.close(force: true);
    }
  };
}

/// Gọi backend: gắn JWT theo [ApiAuth], đổi lỗi thành [ApiException] tiếng Việt, báo 401 cho tầng trên.
/// Không ghi log request/response để JWT và OTP không lọt ra console.
class ApiClient {
  ApiClient({
    String? baseUrl,
    Transport? transport,
    bool? allowInsecure,
    this.tokenFor,
    this.onUnauthorized,
  }) : baseUrl = _trimSlash(baseUrl ?? ApiConfig.baseUrl),
       allowInsecure = allowInsecure ?? kDebugMode,
       _transport = transport ?? ioTransport();

  final String baseUrl;

  /// Cho phép `http://` (chỉ để thử với backend local); bản release luôn bắt buộc https.
  final bool allowInsecure;
  final Transport _transport;

  /// Trả JWT cho loại [ApiAuth] tương ứng (null nếu chưa đăng nhập).
  String? Function(ApiAuth kind)? tokenFor;

  /// Gọi khi máy chủ trả 401 cho request CÓ kèm JWT (phiên hết hạn / bị thu hồi). Đăng nhập sai mật khẩu cũng 401
  /// nhưng không kèm JWT nên không kích hoạt.
  void Function(ApiAuth kind)? onUnauthorized;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  Future<dynamic> get(String path, {ApiAuth auth = ApiAuth.none}) =>
      request('GET', path, auth: auth);

  /// Tải nội dung dạng văn bản (ví dụ CSV), không giải mã JSON. Bỏ BOM đầu file nếu có.
  Future<String> getText(String path, {ApiAuth auth = ApiAuth.none}) async =>
      (await request('GET', path, auth: auth, raw: true)) as String;

  Future<dynamic> post(
    String path, {
    Object? body,
    ApiAuth auth = ApiAuth.none,
    String? token,
  }) => request('POST', path, body: body, auth: auth, token: token);

  Future<dynamic> put(
    String path, {
    Object? body,
    ApiAuth auth = ApiAuth.none,
  }) => request('PUT', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {ApiAuth auth = ApiAuth.none}) =>
      request('DELETE', path, auth: auth);

  /// [token] ghi đè token lấy từ [tokenFor] (dùng khi đăng xuất: phiên đã xoá cục bộ nhưng vẫn cần thu hồi trên máy chủ).
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    ApiAuth auth = ApiAuth.none,
    String? token,
    bool raw = false,
  }) async {
    final uri = Uri.tryParse('$baseUrl$path');
    final okScheme =
        uri != null &&
        (uri.scheme == 'https' || (allowInsecure && uri.scheme == 'http'));
    if (uri == null || uri.host.isEmpty || !okScheme) {
      throw ApiException(
        allowInsecure
            ? 'Địa chỉ máy chủ phải bắt đầu bằng https:// (hoặc http:// khi thử nghiệm).'
            : 'Địa chỉ máy chủ phải bắt đầu bằng https://',
      );
    }

    final jwt = token ?? (auth == ApiAuth.none ? null : tokenFor?.call(auth));
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': ?(jwt == null ? null : 'Bearer $jwt'),
    };

    final HttpResponseData res;
    try {
      res = await _transport(
        HttpRequestData(
          method,
          uri,
          headers,
          body == null ? null : jsonEncode(body),
        ),
      );
    } on TimeoutException {
      throw const ApiException(
        'Máy chủ phản hồi quá chậm, hãy thử lại sau ít giây.',
      );
    } on HandshakeException {
      throw const ApiException('Không thiết lập được kết nối an toàn (https).');
    } on SocketException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng của bạn.',
      );
    } on HttpException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng của bạn.',
      );
    }

    if (res.status >= 200 && res.status < 300) {
      if (raw) {
        return res.body.startsWith('\uFEFF') ? res.body.substring(1) : res.body;
      }
      if (res.body.trim().isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } on FormatException {
        throw const ApiException('Máy chủ trả dữ liệu không đọc được.');
      }
    }

    if (res.status == 401 && jwt != null) onUnauthorized?.call(auth);
    throw ApiException(_messageFor(res), status: res.status);
  }

  /// Đọc `{message}`, `{errors:[...]}` (Identity) hoặc `{errors:{Field:[...]}}` (validation) của backend.
  static String _messageFor(HttpResponseData res) {
    String? message;
    try {
      final data = jsonDecode(res.body);
      if (data is Map) {
        if (data['message'] is String) message = data['message'] as String;
        final errors = data['errors'];
        if (message == null && errors != null) {
          final lines = <String>[];
          if (errors is Map) {
            errors.forEach((field, v) {
              for (final e in v is List ? v : [v]) {
                lines.add(translateServerError('$e', field: '$field'));
              }
            });
          } else if (errors is List) {
            lines.addAll(errors.map((e) => translateServerError('$e')));
          }
          if (lines.isNotEmpty) message = lines.toSet().join('\n');
        }
      }
    } on FormatException {
      // thân phản hồi không phải JSON: dùng thông báo theo mã
    }
    return message ??
        switch (res.status) {
          401 => 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.',
          403 => 'Bạn không có quyền thực hiện thao tác này.',
          404 => 'Không tìm thấy dữ liệu yêu cầu.',
          409 => 'Dữ liệu bị xung đột, hãy tải lại rồi thử lại.',
          423 => 'Đăng nhập sai quá nhiều lần, hãy thử lại sau ít phút.',
          429 => 'Bạn thử quá nhiều lần, hãy chờ một chút rồi thử lại.',
          >= 500 => 'Máy chủ đang gặp sự cố (HTTP ${res.status}), thử lại sau.',
          _ => 'Yêu cầu không thành công (HTTP ${res.status}).',
        };
  }
}

/// Dịch các lỗi tiếng Anh của Identity / DataAnnotations sang tiếng Việt; không khớp thì giữ nguyên.
String translateServerError(String m, {String? field}) {
  final l = m.toLowerCase();
  if (l.contains('already taken')) return 'Email này đã được đăng ký.';
  if (l.contains('at least one digit')) {
    return 'Mật khẩu cần ít nhất một chữ số.';
  }
  if (l.contains('at least one lowercase')) {
    return 'Mật khẩu cần ít nhất một chữ thường.';
  }
  if (l.contains('at least one uppercase')) {
    return 'Mật khẩu cần ít nhất một chữ hoa.';
  }
  if (l.contains('non alphanumeric')) {
    return 'Mật khẩu cần ít nhất một ký tự đặc biệt.';
  }
  if (l.contains('must be at least') && l.contains('password')) {
    return 'Mật khẩu tối thiểu 8 ký tự.';
  }
  final f = field?.toLowerCase();
  if (f == 'password' || f == 'newpassword') {
    return 'Mật khẩu tối thiểu 8 ký tự.';
  }
  if (l.contains('e-mail') || l.contains('invalid email') || f == 'email') {
    return 'Email không hợp lệ.';
  }
  if (f == 'fullname') return 'Họ tên cần từ 2 đến 100 ký tự.';
  if (f == 'nickname') return 'Biệt danh cần từ 1 đến 30 ký tự.';
  if (f == 'birthyear') return 'Năm sinh không hợp lệ.';
  if (f == 'dailylimitminutes') return 'Giới hạn phải từ 5 đến 600 phút.';
  if (f == 'dailywordgoal') return 'Mục tiêu phải từ 1 đến 50 từ.';
  if (l.contains('required')) return 'Vui lòng nhập đủ thông tin.';
  return m;
}
