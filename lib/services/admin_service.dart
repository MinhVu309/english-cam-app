import '../core/api_client.dart';
import '../data/admin/admin_models.dart';
import 'auth_service.dart';

/// Các lệnh gọi quản trị (token Admin). Chỉ là lớp mỏng quanh [ApiClient]; luật nghiệp vụ nằm ở máy chủ.
class AdminService {
  AdminService([ApiClient? api]) : _api = api ?? AuthService.instance.api;

  final ApiClient _api;

  static String _q(Map<String, Object?> params) {
    final parts = [
      for (final e in params.entries)
        if (e.value != null && '${e.value}'.isNotEmpty)
          '${e.key}=${Uri.encodeQueryComponent('${e.value}')}',
    ];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  Future<AdminStats> stats() async => AdminStats.fromJson(
    await _api.get('/api/admin/stats', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  Future<VocabStatus> vocabStatus() async => VocabStatus.fromJson(
    await _api.get('/api/admin/vocab/status', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  // ---------- Người dùng ----------

  Future<PagedList<AdminUser>> users({
    String? search,
    String? role,
    int page = 1,
  }) async => PagedList.fromJson(
    await _api.get(
          '/api/admin/users${_q({'search': search, 'role': role, 'page': page})}',
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
    AdminUser.fromJson,
  );

  Future<AdminUser> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async => AdminUser.fromJson(
    await _api.post(
          '/api/admin/users',
          body: {
            'email': email,
            'password': password,
            'fullName': fullName,
            'role': role,
          },
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
  );

  Future<AdminUser> updateUser(
    String id, {
    required String fullName,
    required String role,
    required bool isActive,
  }) async => AdminUser.fromJson(
    await _api.put(
          '/api/admin/users/$id',
          body: {'fullName': fullName, 'role': role, 'isActive': isActive},
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteUser(String id) =>
      _api.delete('/api/admin/users/$id', auth: ApiAuth.parent);

  // ---------- Chủ đề ----------

  Future<List<AdminCategory>> categories() async => [
    for (final c
        in await _api.get(
              '/api/admin/categories?includeDeleted=true',
              auth: ApiAuth.parent,
            )
            as List<dynamic>)
      AdminCategory.fromJson(c as Map<String, dynamic>),
  ];

  Future<void> createCategory({
    required String id,
    required String vi,
    required String en,
    String? emoji,
    String? color,
  }) => _api.post(
    '/api/admin/categories',
    body: {'id': id, 'vi': vi, 'en': en, 'emoji': emoji, 'color': color},
    auth: ApiAuth.parent,
  );

  Future<void> updateCategory(
    String id, {
    required String vi,
    required String en,
    String? emoji,
    String? color,
  }) => _api.put(
    '/api/admin/categories/$id',
    body: {'vi': vi, 'en': en, 'emoji': emoji, 'color': color},
    auth: ApiAuth.parent,
  );

  Future<void> deleteCategory(String id) =>
      _api.delete('/api/admin/categories/$id', auth: ApiAuth.parent);

  Future<void> restoreCategory(String id) =>
      _api.post('/api/admin/categories/$id/restore', auth: ApiAuth.parent);

  // ---------- Từ ----------

  Future<PagedList<AdminWord>> words({
    String? search,
    String? category,
    bool includeDeleted = false,
    int page = 1,
  }) async => PagedList.fromJson(
    await _api.get(
          '/api/admin/words${_q({'search': search, 'category': category, 'includeDeleted': includeDeleted ? 'true' : null, 'page': page})}',
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
    AdminWord.fromJson,
  );

  Future<AdminWord> createWord(WordDraft w) async => AdminWord.fromJson(
    await _api.post('/api/admin/words', body: w.toJson(), auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  Future<AdminWord> updateWord(String id, WordDraft w) async =>
      AdminWord.fromJson(
        await _api.put(
              '/api/admin/words/$id',
              body: w.toJson(),
              auth: ApiAuth.parent,
            )
            as Map<String, dynamic>,
      );

  Future<void> deleteWord(String id) =>
      _api.delete('/api/admin/words/$id', auth: ApiAuth.parent);

  Future<void> restoreWord(String id) =>
      _api.post('/api/admin/words/$id/restore', auth: ApiAuth.parent);

  /// Tệp đã tải lên theo tiền tố đường dẫn. Không gồm asset đóng gói sẵn trong app (đường dẫn `assets/…`):
  /// từ mới dùng tệp tải lên.
  Future<List<MediaItem>> media({required String prefix}) async {
    final page = PagedList.fromJson(
      await _api.get(
            '/api/admin/media${_q({'prefix': prefix, 'pageSize': 200})}',
            auth: ApiAuth.parent,
          )
          as Map<String, dynamic>,
      MediaItem.fromJson,
    );
    return page.items;
  }

  Future<List<ModelLabel>> modelLabels() async => [
    for (final l
        in await _api.get('/api/admin/vocab/model-labels', auth: ApiAuth.parent)
            as List<dynamic>)
      ModelLabel.fromJson(l as Map<String, dynamic>),
  ];

  // ---------- Xuất bản ----------

  /// Lỗi của bản nháp (rỗng = hợp lệ).
  Future<List<String>> validate() async {
    final j =
        await _api.get('/api/admin/vocab/validate', auth: ApiAuth.parent)
            as Map<String, dynamic>;
    return [for (final e in j['errors'] as List<dynamic>) '$e'];
  }

  Future<ReleaseInfo> publish(String? notes) async {
    final j = await _api.post(
      '/api/admin/vocab/publish',
      body: {'notes': notes},
      auth: ApiAuth.parent,
    );
    return ReleaseInfo.fromJson(j as Map<String, dynamic>);
  }

  Future<List<ReleaseInfo>> releases() async => [
    for (final r
        in await _api.get('/api/admin/vocab/releases', auth: ApiAuth.parent)
            as List<dynamic>)
      ReleaseInfo.fromJson(r as Map<String, dynamic>),
  ];

  // ---------- Góp ý nhận diện ----------

  Future<FeedbackSummary> feedbackSummary() async => FeedbackSummary.fromJson(
    await _api.get('/api/admin/feedback/summary', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  Future<PagedList<AdminFeedback>> feedback({
    bool unknownOnly = false,
    int page = 1,
  }) async => PagedList.fromJson(
    await _api.get(
          '/api/admin/feedback${_q({'unknownOnly': unknownOnly ? 'true' : null, 'page': page})}',
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
    AdminFeedback.fromJson,
  );

  Future<void> deleteFeedback(String id) =>
      _api.delete('/api/admin/feedback/$id', auth: ApiAuth.parent);

  /// CSV (đã bỏ BOM) để dán vào Google Sheets/Excel.
  Future<String> feedbackCsv() =>
      _api.getText('/api/admin/feedback/export.csv', auth: ApiAuth.parent);
}
