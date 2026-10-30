/// Cấu hình kết nối backend. Ghi đè lúc build: `flutter run --dart-define=API_URL=http://10.0.2.2:5080`.
abstract final class ApiConfig {
  /// Địa chỉ API đã deploy (https). Bản release bắt buộc https; bản debug cho phép http để thử với backend chạy local.
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://vuclaude309gmai-001-site1.etempurl.com',
  );

  /// OAuth *Web* client ID, cùng giá trị với `Google:ClientId` của backend. Client ID là định danh công khai, không phải bí mật.
  /// Để trống thì nút Google báo "chưa cấu hình".
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '185827252320-ccaml6efko4me8d6nudimasb7kmft1cg.apps.googleusercontent.com',
  );

  /// Gói từ vựng do chính backend phát (`/api/pack/manifest.json`): mặc định cùng máy chủ với API, nên bố mẹ
  /// không phải nhập địa chỉ nào để cập nhật từ vựng.
  static const packUrl = '$baseUrl/api/pack/';

  // Host miễn phí "ngủ" khi nhàn rỗi nên request đầu có thể chậm 10–30 giây.
  static const connectTimeout = Duration(seconds: 30);
  static const idleTimeout = Duration(seconds: 45);

  /// OTP sống 5 phút và gửi lại cách nhau tối thiểu 1 phút (khớp backend).
  static const otpResendCooldown = Duration(seconds: 60);
}
