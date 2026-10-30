# BACKEND_PLAN.md — Chuyển từ vựng + trò chơi sang ASP.NET Web API

> **Trạng thái (2026-10-30):** GĐ 0–7 xong ở local, trừ email báo cáo tuần (không làm, xem GĐ 7) (bản GĐ 0–3 đã deploy; GĐ 4–7 chạy local, chờ deploy lại) (Google login chưa thử với token thật vì chưa có `Google:ClientId`). Làm **local trước** (SQL Server trong Docker, API chạy `localhost:5080`), **đã deploy bản GĐ 0–3 lên SmarterASP.NET: https://vuclaude309gmai-001-site1.etempurl.com** (đã kiểm tra `/health`, `/api/vocab` khớp `vocab.json`, các endpoint cần đăng nhập trả 401; chưa thử OTP email trên host). Bé đăng nhập **đa thiết bị** (mã liên kết) là phần chính, không còn là "làm nếu còn thời gian". 3 dependency Flutter ở mục 8 đã được duyệt. Tham khảo backend `SmartCheck` (`~/dev mobile/smartcheck/23DTHE1_pham_minh_vu 2`): ASP.NET Core 8, EF Core + SQL Server, Identity, JWT, Email OTP (MailKit), Google idToken, deploy SmarterASP.NET.

## 1. Yêu cầu của thầy → cách đáp ứng

| Yêu cầu | Đáp ứng |
|---|---|
| Có BE API đã deploy | ASP.NET Core 8 trên SmarterASP.NET (như SmartCheck), Swagger luôn bật, URL thật hard-code qua `--dart-define=API_URL` |
| Tách từ vựng + trò chơi sang ASP.NET | Từ vựng/chủ đề/huy hiệu nằm trong DB, có CRUD; game sinh câu hỏi + chấm sao + mở huy hiệu ở server |
| Login / logout | Email + mật khẩu → OTP email; logout = xoá token cục bộ + thu hồi phiên trẻ |
| OTP | Port nguyên `OtpService` (6 số, 5 phút, tối đa 5 lần, băm SHA-256) |
| Đăng nhập Google | Port `google-login` (idToken → JWT). Tài khoản mới mặc định **Parent** |
| CRUD từ vựng | Admin: từ, chủ đề, huy hiệu, file âm thanh/ảnh. Parent: CRUD hồ sơ con |
| 3 role | `Admin`, `Parent`, `Child` (kiểm tra bằng `[Authorize(Roles=…)]` + kiểm tra quyền sở hữu, không chỉ ẩn nút) |
| Dashboard phụ huynh xem tiến độ con | Mục 6 và 7 |

## 2. Quyết định kiến trúc

| Vấn đề | Quyết định | Lý do |
|---|---|---|
| Stack | ASP.NET Core 8, EF Core 8 SQL Server, Identity, JWT — giống SmartCheck | Đã chạy được trên host của bạn; copy được `AuthController`, `OtpService`, `EmailService`, `JwtService`, `UtcDateTimeConverter` |
| Vị trí mã | Thư mục mới `english-cam-ml/english-cam-api/` (namespace `EnglishCam.Api`) | Cạnh `english-cam-app/`, không đụng pipeline ML |
| **ML** | **Vẫn chạy trên máy, không đổi** (`model.tflite` đóng gói trong APK) | PLAN.md: ML đóng băng; ảnh trẻ không rời máy |
| **Offline-first** | App vẫn chạy khi không có mạng: từ vựng đóng gói sẵn là dự phòng, tiến độ ghi cục bộ rồi đồng bộ sau | Host miễn phí "ngủ" (request đầu 10–30 s) — không được để bé chờ |
| Chế độ khách | ~~Chưa đăng nhập = chạy như hiện tại~~ **Đã bỏ (2026-10-30, theo yêu cầu chủ dự án): bắt buộc đăng nhập mới dùng app** (`AuthGate`). Phiên lưu trên máy nên vẫn dùng offline sau khi đăng nhập | Ban đầu giữ trải nghiệm không ép đăng nhập; nay phụ huynh/bé phải có phiên |
| **Phát từ vựng** | API trả `vocab.json` **đúng schema cũ** + endpoint tương thích "gói": `/api/pack/manifest.json`, `/api/pack/vocab.json`, `/api/pack/{path}` | `VocabRepository`, `PackUpdater`, `PackStore`, sha256, fallback asset và test hiện có **dùng lại gần nguyên**, chỉ đổi `PACK_URL` |
| Seed từ vựng | Script import `assets/vocab/vocab.json` (60 từ) vào DB, **giữ nguyên đường dẫn `assets/...`** | Không phải upload lại âm thanh/ảnh; từ mới của admin dùng đường dẫn tương đối + file lưu ở `wwwroot/media` |
| Xoá từ | Xoá mềm (`IsDeleted`) | Tiến độ cũ tham chiếu `WordId` |
| **Nháp / xuất bản** *(thêm ở GĐ 3)* | Admin sửa bản nháp, bấm xuất bản mới tạo `VocabRelease` bất biến (JSON + manifest đã sinh sẵn). Media lưu theo mã băm nội dung | `PackUpdater` bỏ cả lần cập nhật nếu sai 1 byte; sửa dở dang không được lọt tới máy của bé; tải đè file cũ không làm hỏng bản đang phát |
| Nhãn model | Server chỉ chấp nhận `Label` thuộc 24 dòng của `labels.txt` (cấu hình khi seed) | Hợp đồng model (tài liệu hướng dẫn gốc của dự án): admin không được tự bịa nhãn |
| Quản trị | Màn Admin ngay trong app Flutter (như SmartCheck) + Swagger | Không phải làm thêm web |

## 3. Việc phải cập nhật trong tài liệu hiện có (xung đột với quy tắc cũ)

- `PLAN.md` mục 1: "Offline hoàn toàn" và "không thu thập dữ liệu" **không còn đúng** khi có tài khoản + dashboard. Cần ghi rõ: có dữ liệu học tập của bé, nhưng chỉ ở mức tối thiểu (mục 4.3), do phụ huynh sở hữu và xoá được.
- tài liệu hướng dẫn gốc của dự án: thêm mục backend, bỏ câu "Hai phần trong một thư mục" nếu `english-cam-api/` được thêm.
- `docs/VOCAB_PACK.md`: ghi thêm cách lấy gói từ API.

## 4. Vai trò, quyền, dữ liệu

### 4.1 Ma trận quyền

| Hành động | Admin | Parent | Child | Khách |
|---|:-:|:-:|:-:|:-:|
| Đọc từ vựng/chủ đề/huy hiệu | ✔ | ✔ | ✔ | ✔ (công khai) |
| CRUD từ, chủ đề, huy hiệu, media | ✔ | ✘ | ✘ | ✘ |
| CRUD người dùng, đổi role, khoá | ✔ | ✘ | ✘ | ✘ |
| Thống kê toàn hệ thống | ✔ | ✘ | ✘ | ✘ |
| CRUD hồ sơ **con của mình** | ✔ | ✔ | ✘ | ✘ |
| Xem dashboard con **của mình** | ✔ | ✔ | ✘ | ✘ |
| Đặt giới hạn thời gian / mục tiêu cho con | ✘ | ✔ | ✘ | ✘ |
| Chơi game, ghi tiến độ của **chính mình** | ✘ | ✘ | ✔ | ✘ |

Chốt an toàn bắt buộc:
- `register` và `google-login` luôn tạo **Parent**; chỉ Admin đổi được role; Admin đầu tiên do seeder tạo (`Seed:AdminEmail`).
- Mọi endpoint theo `{childId}` phải kiểm tra `child.ParentId == user.Id` (chống IDOR) — có test riêng.
- Child token chỉ gọi được nhóm `/api/progress`, `/api/games`, đọc từ vựng; không gọi được `/api/parent`, `/api/admin`.

### 4.2 Đăng nhập của trẻ — nhiều thiết bị (không có email/mật khẩu)

Trẻ **không tự đăng ký**. Phụ huynh tạo hồ sơ con (biệt danh + avatar). Một bé dùng được **nhiều điện thoại/máy tính bảng cùng lúc** (máy bố, máy mẹ, máy bé), mỗi máy một phiên riêng:

1. **Cùng máy phụ huynh**: phụ huynh đã đăng nhập → chạm hồ sơ con → `POST /api/children/{id}/session {deviceId}` trả JWT role `Child`.
2. **Máy khác (mã liên kết)**: phụ huynh bấm "Thêm thiết bị cho bé" → `POST /api/children/{id}/link-code` trả mã 6 số, sống 10 phút, dùng 1 lần, băm SHA-256, tối đa 5 lần thử (tái dùng cách của `OtpService`). Máy của bé nhập mã ở màn "Bé đăng nhập" → `POST /api/auth/child-link {code, deviceId, deviceName}` trả JWT Child.
3. **Quản lý thiết bị**: mỗi máy một dòng `ChildSession` (tên máy, lần dùng cuối). Phụ huynh xem danh sách, thu hồi từng máy hoặc tất cả (`DELETE /api/children/{id}/sessions/{sid}`). JWT Child sống 30 ngày, kiểm tra `sessionId` trong DB ở mỗi request nên thu hồi có hiệu lực ngay.
4. **Đồng bộ giữa các máy**: sự kiện có `id` do app sinh (idempotent); "từ đã học" lấy hợp giữa các máy, bật/tắt cùng một từ thì bản có `at` mới hơn thắng; sao/ván/huy hiệu do server cộng dồn nên máy nào chơi cũng được tính. Máy mở lại gọi `GET /api/progress/me` để nạp trạng thái mới nhất.
5. Vào khu phụ huynh trên máy của bé vẫn qua cổng toán hiện có (`parent_gate.dart`); sửa/xoá/thu hồi cần JWT của phụ huynh, token Child không làm được.

### 4.3 Mô hình dữ liệu (EF Core)

```
AppUser (Identity)  + FullName, IsActive, CreatedAt           role: Admin | Parent | Child
ChildProfile        Id, UserId(AppUser role Child), ParentId, Nickname, AvatarKey, BirthYear?,
                    DailyLimitMinutes?, DailyWordGoal, IsActive
ChildSession        Id, ChildId, DeviceId, DeviceName, CreatedAt, LastUsedAt, ExpiresAt, Revoked   (nhiều dòng / bé)
ChildLinkCode       Id, ChildId, CodeHash, ExpiresAt, Attempts, Used
OtpCode, (BiometricCredential — tuỳ chọn)               ← copy từ SmartCheck

VocabCategory       Id(slug), ViName, EnName, Emoji, Color, SortOrder
VocabWord           Id(slug = tên file mp3), Label?, En, Vi, Phonetic, ExampleEn, ExampleVi,
                    CategoryId, AudioPath, ExampleAudioPath?, ImagePath?, Emoji?, Hunt, IsDeleted,
                    UpdatedAt
MediaFile           Path, Sha256, Size, ContentType                      ← cho manifest
VocabVersion        Version(int, tăng khi có thay đổi), Notes, CreatedAt

Badge               Id, Name, Description, Emoji, Metric(stars|rounds|perfect|found|learned|streak), Threshold
ChildBadge          ChildId, BadgeId, UnlockedAt

ChildStats          ChildId, Stars, Rounds, PerfectRounds, Found, CurrentStreak, BestStreak, LastActiveDate
ChildWordProgress   ChildId, WordId, Learned, SeenCount, CorrectCount, WrongCount, LastSeenAt, Box(1–5)
GameSession         Id(clientId, idempotent), ChildId, GameType(Match|Hunt), StartedAt, DurationSec,
                    Questions, Correct, StarsEarned, Perfect
GameAnswer          SessionId, WordId, Correct, Attempts
DailyActivity       ChildId, Date, Seconds, WordsLearned, Rounds, Scans
```

Dữ liệu về trẻ giữ **tối thiểu**: biệt danh, năm sinh (tuỳ chọn, không ngày sinh), không ảnh, không tên thật, không vị trí. Không lưu ảnh chụp từ camera. Phụ huynh xoá con = xoá cascade mọi dữ liệu của bé.

## 5. API

Quy ước giống `API.md` của SmartCheck: JSON, `Authorization: Bearer`, enum dạng chuỗi, thời gian UTC có `Z`, lỗi `{message}` / `{errors:[]}`, danh sách phân trang `{total,page,pageSize,items}`.

**Auth** (port từ SmartCheck)
`POST /api/auth/register` · `verify-otp` · `login` · `resend-otp` · `forgot-password` · `reset-password` · `google-login` · `GET/PUT /api/auth/me` · `POST /api/auth/logout` (thu hồi phiên Child nếu có) · `POST /api/auth/child-link` (bé nhập mã trên máy mới)

**Trẻ em** (Parent)
`GET/POST /api/children` · `GET/PUT/DELETE /api/children/{id}` · `PUT /api/children/{id}/settings` · `POST /api/children/{id}/session` · `POST /api/children/{id}/link-code` · `GET /api/children/{id}/sessions` · `DELETE /api/children/{id}/sessions/{sid}` · `POST /api/children/{id}/revoke-sessions`

**Từ vựng**
- Đọc (công khai, có `ETag`/`version`): `GET /api/vocab` (đúng schema `vocab.json`) · `GET /api/vocab/version`
- Tương thích gói: `GET /api/pack/manifest.json` · `GET /api/pack/vocab.json` · `GET /api/pack/{**path}`
- CRUD (Admin): `/api/admin/words` (lọc theo chủ đề, tìm kiếm, phân trang) · `/api/admin/categories` · `POST /api/admin/media` (mp3 ≤ 1 MB, png/jpg ≤ 2 MB; server tính sha256) · `POST /api/admin/vocab/publish` (đóng băng 1 phiên bản + ghi chú)

**Trò chơi** (Child đọc/ghi, Admin CRUD huy hiệu)
- `GET /api/games/match/questions?count=8` — chọn từ **ưu tiên từ bé hay sai / lâu chưa ôn** (hộp Leitner), đáp án nhiễu cùng cách chọn như `buildMatchQuestions` hiện tại
- `GET /api/games/hunt/targets?count=5` — chỉ từ `Hunt = true` có `Label`
- `POST /api/games/sessions` — body `{id, gameType, durationSec, answers:[{wordId, correct, attempts}]}` → server **tự tính** sao, cập nhật hộp từ, streak, mở huy hiệu → `{starsEarned, totalStars, newBadges[]}`; `id` do app sinh nên gửi lại không bị cộng đôi
- `GET /api/games/badges` — danh sách huy hiệu + đã mở chưa · `/api/admin/badges` CRUD

**Tiến độ** (Child)
`POST /api/progress/events` (lô sự kiện, idempotent: `WordLearned`, `WordUnlearned`, `WordScanned`, `ScreenTime`) · `GET /api/progress/me` (nạp lại: từ đã học, sao, huy hiệu, mục tiêu, giới hạn thời gian)

**Dashboard phụ huynh** (Parent, đúng con của mình)
`GET /api/parent/overview` · `GET /api/parent/children/{id}/dashboard?days=7|30` · `GET /api/parent/children/{id}/export.csv`

**Admin**
`/api/admin/users` (danh sách, đổi role, khoá/mở, xoá) · `GET /api/admin/stats`

## 6. Dashboard phụ huynh — nội dung

Một màn "Con của tôi" (chọn bé nếu có nhiều bé), gồm:
1. **Thẻ tóm tắt**: số từ đã học / tổng (vòng tiến độ), sao, số ván, chuỗi ngày học liên tiếp, phút đã chơi hôm nay / giới hạn.
2. **Biểu đồ 7/30 ngày**: phút học mỗi ngày + từ mới mỗi ngày.
3. **Theo chủ đề**: đã học / tổng của từng chủ đề (thanh ngang).
4. **Từ cần ôn**: 5 từ bé sai nhiều nhất (tỉ lệ đúng thấp), kèm nút nghe lại.
5. **Huy hiệu gần đây** và **hoạt động gần đây** (ván nào, vật nào bé đã tìm thấy).
6. **Cài đặt cho bé**: giới hạn phút/ngày, mục tiêu từ/ngày, tắt/bật hồ sơ, thu hồi thiết bị.

Biểu đồ vẽ bằng `CustomPaint` (không thêm `fl_chart`) để khỏi thêm dependency.

## 7. Tính năng thêm (tôi chọn giúp bạn)

**Làm** — mỗi cái đều tận dụng dữ liệu đã có, giá trị rõ cho phụ huynh:

| # | Tính năng | Vì sao |
|---|---|---|
| 1 | **Câu hỏi thích ứng** (hộp Leitner: sai → ôn lại sớm, đúng → giãn ra) | Làm "game ở server" có ý nghĩa; chính là nguồn của "Từ cần ôn" trong dashboard |
| 2 | **Chuỗi ngày học (streak)** + **mục tiêu từ/ngày** | Động lực cho bé, chỉ số dễ đọc cho phụ huynh |
| 3 | **Giới hạn thời gian/ngày** do phụ huynh đặt; app nhắc nhẹ + nghỉ khi hết giờ (Cam nói "Mai chơi tiếp nhé!") | Tính năng trẻ em mà phụ huynh thật sự cần; chỉ cần `DailyActivity.Seconds` |
| 4 | **Thống kê Admin** (người dùng theo role, số bé hoạt động, từ bị sai nhiều nhất toàn hệ thống) | Giúp admin biết từ nào nên sửa/ thêm ví dụ |
| 5 | **Xuất CSV** tiến độ của bé | Rẻ, hữu ích cho báo cáo |

**Làm nếu còn thời gian** *(chưa làm ở GĐ 7: SMTP Gmail trên host chưa kiểm chứng và host miễn phí không chạy job nền ổn định, nên khó chứng minh được)*: email báo cáo tuần cho phụ huynh (`BackgroundService` + `EmailService` sẵn có) · đăng nhập vân tay cho phụ huynh (port `BiometricService`).

**Không làm (cố ý)**: push notification (FCM: thêm dependency + cấu hình, host miễn phí không chạy job nền ổn định) · bảng xếp hạng công khai/chat (an toàn trẻ em) · quảng cáo · từ vựng riêng của gia đình (để dành sau) · ML trên server.

## 8. Thay đổi phía Flutter (`english-cam-app/`)

- **Dependency cần bạn duyệt** (PLAN.md: hỏi trước khi thêm): `flutter_secure_storage` (lưu JWT), `google_sign_in`, `device_info_plus` (DeviceId). HTTP dùng lại `dart:io HttpClient` như `pack_updater.dart` — **không** thêm `dio`/`provider` (app đang dùng `ChangeNotifier` singleton).
- Mới: `lib/core/api_client.dart` (base URL, header, timeout 40 s cho host ngủ, map lỗi sang tiếng Việt) · `lib/services/auth_service.dart` · `lib/services/sync_service.dart` (hàng đợi sự kiện lưu `shared_preferences`, gửi lại khi có mạng) · `lib/features/auth/*` (đăng ký, OTP, quên mật khẩu, Google) · `lib/features/parent/*` (danh sách con, dashboard, cài đặt cho bé) · `lib/features/admin/*` (CRUD từ, chủ đề, huy hiệu, người dùng).
- Sửa: `ProgressService`/`GameProgress` giữ API hiện tại nhưng sau mỗi thay đổi ghi thêm 1 sự kiện vào hàng đợi; khi đăng nhập con thì **gộp (hợp)** tiến độ khách vào tài khoản. `matching_game_screen` / `hunt_game_screen`: thử lấy câu hỏi từ API, lỗi/offline → `buildMatchQuestions` cục bộ như cũ. `AppSettings.kDefaultPackUrl` → `…/api/pack/`; kiểm tra cập nhật nền khi mở app (không chặn UI).
- `badges.json` giữ làm dự phòng offline; huy hiệu lấy từ API khi có mạng.
- `router.dart`: điều hướng theo role sau đăng nhập (Admin → quản trị, Parent → khu phụ huynh/chọn bé, Child → Home như hiện nay).
- `tool/check_assets.dart` vẫn dùng cho dữ liệu đóng gói; thêm lệnh kiểm tra `GET /api/vocab` khớp `labels.txt`.

## 9. Các giai đoạn

| GĐ | Nội dung | Xong khi |
|---|---|---|
| **0** ✔ | **Local trước.** Docker SQL Server (cổng 1434), project `english-cam-api` (migrations, `/health`, Swagger), cập nhật PLAN.md/tài liệu hướng dẫn gốc của dự án. *Hoãn sang lúc deploy:* tên site + DB SmarterASP.NET, Gmail App Password, Google OAuth client (Android client mới: package `com.englishcam.english_cam` + SHA-1) | `docker compose up -d` → `dotnet run` → `GET /health` trả `database: connected`. OTP in ra console khi chưa có SMTP; Google login thử ở GĐ 1 khi đã có `Google:ClientId` |
| **1** ✔ (local) | Khung API + Auth (register/OTP/login/forgot/Google/me/logout) + 3 role + seed Admin. *Chưa deploy* (làm ở cuối) | Đã chạy thử bằng curl: đăng ký → OTP → JWT, đăng nhập 2 bước, quên mật khẩu (token cũ chết), đăng xuất, khoá sau 5 lần sai, Admin seed. Google login mới thử nhánh chưa cấu hình (503) |
| **2** | `ChildProfile`, phiên Child **nhiều thiết bị** (cùng máy + mã liên kết), danh sách/thu hồi thiết bị, CRUD con, `/api/admin/users`, test IDOR | Parent A không đọc/sửa được con của Parent B; 2 thiết bị cùng đăng nhập 1 bé, thu hồi 1 máy thì máy kia vẫn chạy (test đạt) |
| **3** ✔ (local) | Từ vựng: entity + seed 60 từ, CRUD admin (từ, chủ đề, media), **bản nháp → xuất bản**, `/api/vocab`, `/api/pack/*`, upload media | 51 test đạt. `/api/vocab` giống từng trường với `vocab.json` trong app. `PackUpdater` thật của app tải gói từ API (3 file, sha256 đúng), nạp 61 từ, lần hai không tải lại |
| **4** ✔ | Flutter: `ApiClient`, `AuthService`, đăng ký/OTP/đăng nhập/quên mật khẩu/Google, hồ sơ bé (CRUD, thiết bị, mã liên kết), nhập mã trên máy của bé, điều hướng theo role (Admin → trang quản trị tối giản, Parent → Hồ sơ của bé, Child → Home), chế độ khách giữ nguyên | `flutter analyze` sạch; 132 test đạt (62 mới); client Dart thật chạy trọn luồng với API thật (đăng ký → OTP → bé 2 máy → thu hồi → đăng xuất → admin); APK debug và release build được. **Chưa thử trên máy thật**, và Google Sign-In chưa thử (cần Android OAuth client) |
| **5** ✔ (local) | Game + tiến độ: câu hỏi thích ứng (Leitner), `sessions`, `events`, `progress/me`, huy hiệu ở server (+ CRUD admin), chuỗi ngày, xoá tiến độ từ xa; Flutter: `SyncService` (hàng đợi offline-first, id idempotent), mỗi hồ sơ bé một ngăn lưu cục bộ, đo thời gian dùng | Server 99 test đạt (kể cả đột biến: sai luật sao / bỏ chống trùng đều bị test bắt). App 163 test đạt. Client thật + server thật: chơi → mất mạng (giữ hàng đợi) → có mạng (gửi bù) → máy thứ hai nhận đủ tiến độ → bố mẹ xoá tiến độ, đều đúng |
| **6** ✔ (local) | Dashboard phụ huynh: `/api/parent/overview`, `/dashboard?days=`, `/export.csv`; Flutter: thẻ tóm tắt trong danh sách bé, màn *Tiến độ* (vòng tiến độ, 2 biểu đồ cột vẽ bằng CustomPaint, theo chủ đề, từ cần ôn có nút nghe lại, huy hiệu, hoạt động gần đây, chép CSV) | Server 126 test đạt (đột biến: bỏ kiểm tra quyền / đảo thứ tự từ yếu đều bị bắt). App 186 test đạt. Client Dart thật + server thật: số liệu dashboard khớp, CSV giữ tiếng Việt, người lạ nhận 404 |
| **7** ✔ (local) | Giới hạn thời gian chơi **được thực thi** trong app (`PlayLimit`: khoá toàn app khi hết giờ, bố mẹ qua cổng phép nhân cho chơi thêm 10/20/30 phút, Cam nhắc trước 5 phút, nhớ theo từng bé nên tắt mạng/mở lại app không né được, đứng ở màn khoá không tính giờ); `GET /api/admin/stats` (người dùng theo role, bé hoạt động, máy liên kết, hoạt động 7 ngày, 10 từ bị sai nhiều nhất); màn quản trị trong app: số liệu, người dùng (tìm/lọc/thêm/sửa/khoá/xoá), từ vựng (tìm/lọc/thêm/sửa/xoá/khôi phục), chủ đề, kiểm tra + xuất bản. **Chưa làm:** tải tệp âm thanh/ảnh từ app (cần thư viện chọn tệp, chưa được duyệt; vẫn tải bằng Swagger), CRUD huy hiệu trong app (API đã có), email báo cáo tuần | Server 131 test đạt (5 mới; đột biến: đảo thứ tự/bỏ ngưỡng 5 lượt đều bị bắt). App 236 test đạt (gồm cổng đăng nhập bắt buộc ở bước sau GĐ 7; 41 mới ở GĐ 7; đột biến: bỏ bù phần vượt, vẫn đếm giờ khi khoá, bỏ phần chưa gửi, cho tự khoá mình, bỏ xác nhận xuất bản đều bị bắt). Client Dart thật + API thật: server ghi 330 giây khớp máy, 10 phút ở màn khoá không tính, tăng giới hạn thì mở khoá; AdminService thật chạy đủ stats/users/words/categories/validate. **Chưa thử trên máy thật** |
| **8** *(làm dở)* | Kiểm thử + tài liệu + deploy cuối: xUnit (streak, Leitner, huy hiệu, quyền sở hữu, OTP), `flutter test`, `docs/API.md`, README backend, ảnh chụp màn hình, cập nhật báo cáo | Chạy được toàn bộ luồng trên URL deploy, không dùng localhost |

> **Kiểm chứng trên URL deploy (2026-10-30):** đã chạy trên Pixel 7 với `https://vuclaude309gmai-001-site1.etempurl.com` (không localhost): đăng ký + OTP qua email thật, tạo bé, giới hạn thời gian (khoá đúng 5 phút), 2 game, camera, cập nhật từ vựng không nhập link, dashboard, liên kết máy thứ hai nhận lại tiến độ. **Góp ý nhận diện sai** cũng đã chạy trên host (4 lần sửa trên cùng một ảnh, máy chủ chấp nhận; chưa đọc phía máy chủ vì cần Admin). **Chưa chạy trên host:** khu Admin (cần tài khoản Admin của host), Google Sign-In, xuất bản từ vựng. Chi tiết và ảnh ở `demo.md` mục 13.

**Thứ tự ưu tiên nếu thiếu thời gian**: 1 → 2 → 3 → 4 → 6 → 5 → 7. (Bắt buộc theo đề: có API deploy, auth/OTP/Google, CRUD từ vựng, 3 role, dashboard; game ở server là phần "tách" nên đừng bỏ, nhưng phần thích ứng/streak có thể rút gọn.)

## 10. Deploy & vận hành

**Chạy local (hiện tại):** `docker compose up -d` (SQL Server, cổng host **1434**) → `dotnet run` (API ở `http://0.0.0.0:5080`, Swagger `/swagger`). Máy thật cùng Wi-Fi gọi `http://<IP-máy-Mac>:5080` (Android release chặn http, nên dùng bản debug hoặc cấu hình riêng cho local). Deploy lên SmarterASP.NET làm ở GĐ cuối.

- `net8.0`, `AspNetCoreHostingModel=OutOfProcess`, loại `publish/**` khỏi glob — copy từ csproj SmartCheck. `appsettings.json` và `appsettings.Production.json` **không commit** (kèm `appsettings.example.json` + `.gitignore`).
- Cấu hình: `ConnectionStrings`, `Jwt:Key` (≥ 32 ký tự), `Smtp:*`, `Google:ClientId`, `Seed:AdminEmail/AdminPassword`. Giữ `docker-compose.yml` SQL Server cho máy dev.
- Dùng **EF migrations** thay `EnsureCreated` (SmartCheck phải vá bảng bằng SQL tay vì `EnsureCreated`; tránh lặp lại).
- Media lưu `wwwroot/media/` — host miễn phí có hạn mức dung lượng, nên chỉ từ mới của admin mới tốn chỗ; 60 từ gốc vẫn nằm trong APK.
- Release Android: https bắt buộc (đã có trong `PackUpdater`); quyền `INTERNET` đã có.

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Host miễn phí ngủ / có thể bị khoá lúc chấm bài | Offline-first; deploy sớm ở GĐ 1; kiểm tra lại URL trước ngày nộp; chuẩn bị `docker-compose` + video quay luồng chạy dự phòng |
| Google Sign-In lỗi cấu hình (SHA-1, package) | Làm ở GĐ 0–1, thử trên máy thật trước khi làm tiếp |
| Gmail SMTP chặn / hạn mức | OTP in ra log khi chưa cấu hình (đã có trong `EmailService`) để test; dùng App Password |
| Dữ liệu trẻ em | Mục 4.3: tối thiểu hoá, phụ huynh sở hữu và xoá được; nêu rõ trong báo cáo |
| Client và server lệch schema từ vựng | API trả đúng schema `vocab.json`; `VocabRepository._validate` vẫn là chốt chặn, hỏng thì rơi về asset đóng gói |
| Game ở server bị cheat (gửi `correct=true` bừa) | Chấp nhận được với app học của trẻ; server giới hạn sao/ván và số ván/giờ |

## 12. Đã chốt / còn mở

Đã chốt: làm local với SQL Server Docker trước · duyệt `flutter_secure_storage`, `google_sign_in`, `device_info_plus` · bé đăng nhập đa thiết bị bằng mã liên kết.

Còn mở: hạn nộp bài (để biết cắt GĐ 7 đến đâu) · host deploy (dùng lại SmarterASP.NET của SmartCheck hay chỗ khác).
