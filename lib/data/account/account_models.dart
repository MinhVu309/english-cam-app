/// Vai trò theo máy chủ: Admin / Parent / Child.
enum UserRole {
  admin,
  parent,
  child;

  static UserRole parse(String? s) => switch (s?.toLowerCase()) {
    'admin' => UserRole.admin,
    'child' => UserRole.child,
    _ => UserRole.parent,
  };
}

/// Kết quả đăng nhập của máy chủ (`AuthResultDto`): JWT, hạn dùng và thông tin người dùng.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.role,
    required this.userId,
    required this.fullName,
    required this.email,
  });

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    token: j['token'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String).toUtc(),
    role: UserRole.parse(j['role'] as String?),
    userId: j['userId'] as String,
    fullName: j['fullName'] as String? ?? '',
    email: j['email'] as String? ?? '',
  );

  final String token;
  final DateTime expiresAt;
  final UserRole role;
  final String userId;
  final String fullName;
  final String email;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, dynamic> toJson() => {
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'role': role.name,
    'userId': userId,
    'fullName': fullName,
    'email': email,
  };
}

/// Hồ sơ của một bé (`ChildDto`).
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.nickname,
    this.avatarKey,
    this.birthYear,
    this.dailyLimitMinutes,
    this.dailyWordGoal = 5,
    this.isActive = true,
    this.activeDevices = 0,
    this.lastActiveAt,
  });

  factory ChildProfile.fromJson(Map<String, dynamic> j) => ChildProfile(
    id: j['id'] as String,
    nickname: j['nickname'] as String,
    avatarKey: j['avatarKey'] as String?,
    birthYear: j['birthYear'] as int?,
    dailyLimitMinutes: j['dailyLimitMinutes'] as int?,
    dailyWordGoal: j['dailyWordGoal'] as int? ?? 5,
    isActive: j['isActive'] as bool? ?? true,
    activeDevices: j['activeDevices'] as int? ?? 0,
    lastActiveAt: j['lastActiveAt'] == null
        ? null
        : DateTime.parse(j['lastActiveAt'] as String).toUtc(),
  );

  final String id;
  final String nickname;
  final String? avatarKey;
  final int? birthYear;
  final int? dailyLimitMinutes;
  final int dailyWordGoal;
  final bool isActive;
  final int activeDevices;
  final DateTime? lastActiveAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'avatarKey': avatarKey,
    'birthYear': birthYear,
    'dailyLimitMinutes': dailyLimitMinutes,
    'dailyWordGoal': dailyWordGoal,
    'isActive': isActive,
    'activeDevices': activeDevices,
    'lastActiveAt': lastActiveAt?.toIso8601String(),
  };
}

/// Một thiết bị đã đăng nhập cho bé (`ChildSessionDto`).
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.expiresAt,
    this.lastUsedAt,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
    id: j['id'] as String,
    deviceName: j['deviceName'] as String? ?? 'Thiết bị',
    createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
    expiresAt: DateTime.parse(j['expiresAt'] as String).toUtc(),
    lastUsedAt: j['lastUsedAt'] == null
        ? null
        : DateTime.parse(j['lastUsedAt'] as String).toUtc(),
  );

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastUsedAt;
}

/// Mã 8 số để bé nhập trên máy khác.
class LinkCode {
  const LinkCode({required this.code, required this.expiresAt});

  factory LinkCode.fromJson(Map<String, dynamic> j) => LinkCode(
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String).toUtc(),
  );

  final String code;
  final DateTime expiresAt;

  /// `1234 5678` cho dễ đọc.
  String get pretty =>
      code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
}
