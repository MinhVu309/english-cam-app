# English Cam — Kịch bản demo 7 phút và bản đồ flow tính năng

Tài liệu này cho **người thuyết trình** và **3 thành viên hỗ trợ**. Phần A giúp hiểu toàn bộ tính năng chạy thế nào. Phần B là kịch bản từng phút. Phần C là phân vai. Phần D là chuẩn bị, phương án dự phòng và câu hỏi hay gặp.

Mọi con số trong tài liệu lấy từ lần chạy thật (xem `docs/demo.md`, `docs/TEST_REPORT.md`, `reports/classification_report.txt`). Chỗ nào chưa kiểm chứng thì ghi rõ là **chưa kiểm chứng**.

---

## A. Hiểu sản phẩm trong 1 phút

**English Cam** là app Android (có cả bản iOS) dạy từ vựng tiếng Anh cho trẻ em: bé chụp một đồ vật, app nhận ra nó là gì, đọc to tên tiếng Anh, rồi bé học thêm bằng từ vựng và game. Bố mẹ quản lý bé qua tài khoản.

Ba khối:

```
┌────────────────────┐   HTTPS + JWT    ┌─────────────────────────┐
│  App Flutter       │ ───────────────► │ Backend ASP.NET Core 8  │
│  - Model TFLite    │ ◄─────────────── │ + SQL Server            │
│    chạy TRÊN MÁY   │  chỉ gửi chữ,    │ - đăng nhập OTP/Google  │
│  - Học, game, offline│ không gửi ảnh  │ - từ vựng, game, tiến độ│
│  - Hàng đợi đồng bộ│                  │ - dashboard, admin      │
└────────────────────┘                  └─────────────────────────┘
        ▲
        │ ML huấn luyện bằng Python/TensorFlow (MobileNetV2) -> model.tflite
        │ 24 lớp vật, độ chính xác trên tập test 88,84%
```

Ba vai trò: **Phụ huynh** (đăng ký, tạo bé, xem dashboard), **Bé** (học và chơi, vào bằng hồ sơ trên máy bố mẹ hoặc mã liên kết 8 số), **Admin** (sửa từ vựng, xuất bản, xem thống kê và góp ý).

### Điểm "xịn" nên nhấn mạnh (theo thứ tự ưu tiên)

| # | Điểm nổi bật | Vì sao đáng khoe |
|---|---|---|
| 1 | **Nhận diện đồ vật bằng AI chạy ngay trên điện thoại** | Không cần mạng, ảnh của bé không bao giờ rời máy (riêng tư). Có model tự huấn luyện, 24 lớp. |
| 2 | **Vòng góp ý khi nhận diện sai** | Bé chọn lại trong top-3 hoặc tự gõ tên, app gửi **chỉ chữ** lên server để cải thiện sau. |
| 3 | **Giới hạn thời gian chơi do bố mẹ đặt, máy tự khoá** | Khoá đè lên mọi màn, mở lại bằng cổng phép nhân của bố mẹ. |
| 4 | **Server quyết định game và tiến độ** | Sao, huy hiệu, chuỗi ngày, ôn tập Leitner do server tính, gửi lại không bị cộng đôi. |
| 5 | **Dashboard phụ huynh** | Số liệu tính ở server: từ đã học, sao, độ chính xác, chủ đề, huy hiệu; chép dữ liệu CSV sang Sheets/Excel. |
| 6 | **Từ vựng mới tự báo, bấm một nút để cập nhật** | Admin xuất bản, máy của bé tự hiện thông báo, không phải nhập link. |
| 7 | **Offline-first** | Mất mạng vẫn học, ghi vào hàng đợi, có mạng thì tự gửi bù. |
| 8 | **Một bé dùng nhiều máy** | Nhập mã liên kết 8 số, tiến độ hợp nhất giữa các máy. |

---

## A2. Flow từng tính năng (để hiểu và trả lời câu hỏi)

### 1. Cổng đăng nhập (bắt buộc)
- Mở app mà chưa có phiên: hiện màn chào với hai nút **Bố mẹ đăng nhập** và **Máy của bé nhập mã liên kết**. Không đăng nhập thì không vào được app.
- Đã có phiên thì **không** hiện cổng, kể cả khi mất mạng (JWT lưu bằng `flutter_secure_storage`).
- Phụ huynh: đăng ký email + mật khẩu → server gửi **mã OTP qua email** (Gmail SMTP) → nhập OTP → vào. Có thêm Google Sign-In (**chưa kiểm chứng**, cần OAuth client Android) và quên mật khẩu.
- Nút Back của Android đi qua `BackInterceptor`, không thoát nhầm app.

### 2. Hồ sơ bé và mã liên kết
- Phụ huynh vào **Quản lý** → thêm bé (biệt danh, hình đại diện, mục tiêu từ/ngày) → bật **Giới hạn thời gian chơi** (phút/ngày).
- Cách cho bé vào: (a) bố mẹ chọn hồ sơ bé trên máy mình; (b) tạo **mã liên kết 8 số**, nhập trên máy của bé.
- Mỗi hồ sơ có **ngăn lưu riêng** trên máy (khoá `p.<userId>.…`), hai bé dùng chung máy không lẫn tiến độ.

### 3. Chụp & Học (trái tim của app)
1. Home → **Chụp & Học** → màn camera (xin quyền camera lần đầu) → **Chụp ảnh** → **Xong**.
2. Model TFLite chạy trong isolate riêng (2 luồng CPU), ảnh được đưa về 224×224, trả **top-3**. Chỉ hiện kết quả khi xác suất **≥ 0,7**; thấp hơn thì app nói "Mình chưa chắc, thử chụp lại nhé!".
3. Kết quả: ảnh minh hoạ, tên tiếng Anh/tiếng Việt, phát âm (mp3 đóng gói sẵn), mascot **Cam** nói động viên. Có nút nghe lại, lưu vào tiến độ.
4. 24 lớp: book, pen, bag, ruler, scissors, clock, cup, bottle, chair, table, bowl, spoon, shoe, hat, glasses, umbrella, toothbrush, towel, apple, banana, orange, ball, teddy_bear, toy_car.
5. **Điểm yếu đã biết (đừng chọn làm vật demo):** `apple` recall thấp, `table` hay bị đoán nhầm; mặt người từng bị đoán là "hat". Vật nên dùng demo: **cup, bottle, book, banana, ball, teddy_bear** (tập thử trước, xem mục D).

### 4. Góp ý khi nhận diện sai
- Ở màn kết quả bấm **Không đúng?** → chọn một trong top-3 hoặc **Khác…** → hộp thoại "Đó là gì nhỉ?" cho gõ tên (gợi ý từ từ vựng, gõ không dấu vẫn ra: "cai ban" → "cái bàn").
- Xong hiện lời cảm ơn: "Sự góp ý của bạn là đóng góp lớn cho ứng dụng sau này".
- Kỹ thuật: lưu vào **hàng đợi bền** trên máy → tự gửi (đợi 3 giây, khi quay lại app, khi đăng nhập) tới `POST /api/feedback/recognition`. Mỗi ảnh có một `id`: chọn lại thì **cập nhật cùng một góp ý**. Lỗi mạng/5xx/429/401 thì giữ lại, 400/409 thì bỏ, quá 7 ngày thì bỏ.
- **Quy tắc cứng: chỉ gửi chữ** (nhãn model, xác suất, top-3, từ đúng), **không bao giờ gửi ảnh**.
- Admin xem trong **Góp ý nhận diện** (lọc, tổng hợp, xuất CSV).

### 5. Từ vựng
- 60 từ (24 khớp model + 36 chỉ để học), chia chủ đề, **cả 60 từ có ảnh thật**. Bấm vào từ: ảnh lớn, nghĩa, ví dụ, nghe phát âm.
- Từ vựng nằm trong `assets/vocab/vocab.json`, không hardcode trong code. Ảnh tìm theo **mã từ**, nên vẫn hiện khi từ vựng đến từ gói cập nhật.

### 6. Game
- **Nghe & chọn hình**: app đọc từ, bé chọn đúng hình. Câu hỏi lấy từ server (chờ tối đa 3 giây, lỗi/offline thì tự tạo như cũ). Cuối ván có tổng kết, sao, huy hiệu.
- **Tìm vật**: app nêu từ, bé đi tìm vật thật rồi chụp bằng camera; model xác nhận. Dùng được vì model nhận 24 lớp.
- Server tính sao, huy hiệu, chuỗi ngày, hộp Leitner (ôn lại từ hay sai). Ván và sự kiện có `id` do app sinh nên gửi lại không bị cộng đôi.

### 7. Giới hạn thời gian chơi
- Server chỉ lưu **giới hạn** và **số giây đã dùng**; **máy tự khoá**. Số đã dùng = số trên server + phần chưa gửi + thời gian đang mở.
- Còn 5 phút thì cảnh báo một lần. Hết giờ: màn khoá phủ lên mọi thứ (kể cả hộp thoại đang mở). Bấm **Dành cho bố mẹ** → giải phép nhân → chọn thêm 10/20/30 phút. Phần vượt được tính bù và hiện ở dashboard.

### 8. Dashboard phụ huynh
- Cài đặt → tài khoản phụ huynh → **Tiến độ** của bé: tóm tắt (từ đã học, sao, độ chính xác, chuỗi ngày), theo chủ đề, huy hiệu, hoạt động gần đây; nút **chép dữ liệu CSV** (vào clipboard để dán vào Sheets/Excel, không tạo file).
- Biểu đồ vẽ bằng `CustomPaint` (không dùng thư viện biểu đồ). Ngày tính theo giờ Việt Nam (UTC+7). Mọi API theo `{childId}` kiểm tra phụ huynh có sở hữu bé không (chống IDOR).

### 9. Cập nhật từ vựng từ xa (tự báo)
- Admin sửa **bản nháp** → bấm **Xuất bản** → server tạo bản mới.
- App tự hỏi `manifest.json` lúc mở app, khi vừa đăng nhập, khi quay lại app, mỗi 30 phút; có bản mới thì hiện **một thông báo mỗi phiên bản**. Vào Cài đặt (sau cổng phụ huynh) → **Cập nhật từ vựng** → nút **Cập nhật ngay (bản N)**. Tự tải, kiểm tra sha256, đổi sang bản mới; hỏng thì tự rơi về bản đóng gói sẵn.
- Chỉ là thông báo trong app, **không phải push của hệ điều hành** (chưa dùng FCM).

### 10. Đồng bộ offline-first và nhiều máy
- Mọi tiến độ ghi ngay vào máy và vào hàng đợi, có mạng thì gửi; sau đó máy đặt lại số liệu theo trạng thái server.
- Máy thứ hai: nhập mã liên kết → cùng một bé, tiến độ gộp lại.

### 11. Khu quản trị (Admin)
- Số liệu tổng, quản lý người dùng, từ vựng (thêm/sửa), chủ đề, **xuất bản**, góp ý nhận diện.
- **Lưu ý:** trên host đã deploy **không có tài khoản Admin**; phần này chạy được ở backend local. Xem phương án dự phòng ở mục D.

---

## A3. Bản đồ API theo tính năng

Backend: ASP.NET Core 8, tài liệu tương tác tại `<host>/swagger`, kiểm tra sống tại `GET /health`. Mọi API (trừ nhóm "công khai") cần header `Authorization: Bearer <JWT>`. Danh sách dưới lấy từ các controller trong `english-cam-api/Controllers/` và đối chiếu với nơi app gọi (`lib/services/`).

**Ba loại token (role trong JWT):** `Parent` (phụ huynh), `Child` (bé), `Admin`. Server chặn theo role: gọi sai role trả 403, không có token trả 401. Máy giữ được cùng lúc token phụ huynh và token bé.

### A3.1 Đăng nhập, đăng ký (nhóm `/api/auth`, công khai trừ khi ghi khác)

| Bước trong app | API | Ghi chú |
|---|---|---|
| Đăng ký | `POST /api/auth/register` | Luôn tạo role **Parent**; email chưa xác minh; server gửi mã OTP 6 số qua Gmail SMTP |
| Nhập OTP | `POST /api/auth/verify-otp` | Đúng mã thì xác minh email và trả `{token, expiresAt, role, userId, fullName, email}` |
| Không nhận được mã | `POST /api/auth/resend-otp` | Gửi mã mới thì **mã cũ vô hiệu** |
| Đăng nhập | `POST /api/auth/login` | Trả JWT |
| Quên mật khẩu | `POST /api/auth/forgot-password` rồi `POST /api/auth/reset-password` | Dùng OTP qua email |
| Google | `POST /api/auth/google-login` | Luôn tạo Parent. **Chưa kiểm chứng** |
| Đăng xuất | `POST /api/auth/logout` (cần token) | |
| Xem/sửa hồ sơ | `GET /api/auth/me`, `PUT /api/auth/me` (Parent, Admin) | |
| Bé nhập mã liên kết | `POST /api/auth/child-link` | Mã 8 số, sống **10 phút**, dùng **một lần**; giới hạn **10 lần/phút/IP** (429 nếu vượt) |

Khi token đã gắn mà server trả **401** thì app xoá phiên và hiện thông báo, rồi `AuthGate` đưa về màn chào.

### A3.2 Hồ sơ bé (nhóm `/api/children`, Parent/Admin)

Mọi API có `{id}` đều kiểm tra phụ huynh **sở hữu bé** (chống IDOR); không phải của mình thì trả 404.

| Bước trong app | API |
|---|---|
| Danh sách bé / tạo bé | `GET /api/children`, `POST /api/children` |
| Xem / sửa / xoá bé | `GET/PUT/DELETE /api/children/{id}` |
| Mục tiêu từ/ngày và **giới hạn giờ chơi** | `PUT /api/children/{id}/settings` |
| Xoá tiến độ của bé | `DELETE /api/children/{id}/progress` |
| **Cho bé vào máy mình** (chọn hồ sơ) | `POST /api/children/{id}/session` → trả token role Child |
| **Tạo mã liên kết** cho máy khác | `POST /api/children/{id}/link-code` |
| Xem các máy đang đăng nhập của bé | `GET /api/children/{id}/sessions` |
| Thu hồi một máy / mọi máy | `DELETE /api/children/{id}/sessions/{sessionId}`, `POST /api/children/{id}/revoke-sessions` |

Máy của bé (token Child) tự đọc hồ sơ của mình bằng `GET /api/child/me`.

### A3.3 Tiến độ và đồng bộ (nhóm `/api/progress`, token Child)

| Việc | API | Nội dung |
|---|---|---|
| Lấy trạng thái | `GET /api/progress/me` | Sao, ván, chuỗi ngày, từ đã học, huy hiệu, **mục tiêu/giới hạn của bố mẹ**, hoạt động hôm nay |
| Gửi sự kiện (tối đa 200/lô) | `POST /api/progress/events` | Ba loại: `learned` (đánh dấu đã học), `scan` (nhận ra vật qua camera), `screenTime` (số giây dùng app). Mỗi sự kiện có `id` do app sinh, gửi lại không bị cộng đôi; sự kiện sai bị bỏ và đếm trong `ignored` |

Cách app dùng: ghi vào máy và hàng đợi **trước**, có mạng thì `POST events`, xong `GET me` để đặt lại số liệu theo server. `screenTime` chính là nguồn của giới hạn giờ chơi.

### A3.4 Game (nhóm `/api/games`, token Child)

| Việc | API | Ghi chú |
|---|---|---|
| Câu hỏi "Nghe & chọn hình" | `GET /api/games/match/questions?count=8` | Ưu tiên từ bé hay sai hoặc chưa gặp (Leitner), chỉ từ **đã xuất bản** và có hình; cần ≥ 4 từ có hình. App chờ tối đa 3 giây, lỗi/offline thì tự tạo câu hỏi |
| Vật cần tìm cho "Tìm vật" | `GET /api/games/hunt/targets?count=5` | Chỉ từ có nhãn model, ưu tiên từ bé ít thuộc |
| Nộp một ván | `POST /api/games/sessions` | App chỉ gửi **danh sách đáp án**; server tự tính sao, huy hiệu, chuỗi ngày. Gửi lại cùng `id` trả `duplicate: true`. Nhiều quá trả 429, mâu thuẫn trả 409 |
| Huy hiệu | `GET /api/games/badges` | Kèm trạng thái đã mở |

### A3.5 Giới hạn giờ chơi

Không có API riêng: nó đi bằng hai API ở trên.
- Bố mẹ đặt: `PUT /api/children/{id}/settings`.
- Máy bé biết giới hạn qua `GET /api/progress/me`, gửi số giây dùng qua `POST /api/progress/events` (loại `screenTime`).
- **Server chỉ lưu giới hạn và số giây; máy tự khoá.** Số đã dùng = số trên server + phần chưa gửi + thời gian đang mở. Cho chơi thêm là xử lý trên máy qua cổng phép nhân.

### A3.6 Dashboard phụ huynh (nhóm `/api/parent`, Parent/Admin)

| Việc | API |
|---|---|
| Thẻ tóm tắt tất cả bé | `GET /api/parent/overview` |
| Dashboard một bé | `GET /api/parent/children/{id}/dashboard?days=7` (1–90 ngày) |
| Xuất CSV | `GET /api/parent/children/{id}/export.csv?kind=daily` hoặc `kind=words`, kèm `&days=…` |

Chỉ đọc, đếm trên bản từ vựng **đã xuất bản**; ngày chia theo giờ Việt Nam (UTC+7). CSV là UTF-8 có BOM (Excel đọc đúng tiếng Việt) và chặn CSV injection. Trong app, nút CSV chép dữ liệu vào clipboard.

### A3.7 Từ vựng và cập nhật từ xa (công khai, **không cần token**)

| Việc | API | Ghi chú |
|---|---|---|
| Toàn bộ từ vựng | `GET /api/vocab` | Đúng schema `assets/vocab/vocab.json` của app; dùng ETag, chưa đổi thì trả **304** |
| Chỉ số phiên bản | `GET /api/vocab/version` | `{version, notes, createdAt}` |
| Gói cập nhật cho app | `GET /api/pack/manifest.json`, `GET /api/pack/vocab.json`, và các file âm thanh/ảnh khai báo trong manifest | App mặc định lấy từ `<API_URL>/api/pack/`. `PackWatcher` chỉ hỏi `manifest.json`, `PackUpdater` tải từng file và kiểm tra sha256 |

Luồng cập nhật: Admin `POST /api/admin/vocab/publish` → có `VocabRelease` mới → `PackWatcher` thấy `manifest.json` có version lớn hơn bản trên máy → báo một lần mỗi phiên bản → bấm "Cập nhật ngay" → tải và đổi sang bản mới.

### A3.8 Góp ý nhận diện sai (token bất kỳ đã đăng nhập)

| Việc | API | Ghi chú |
|---|---|---|
| Gửi / cập nhật góp ý | `POST /api/feedback/recognition` | **Upsert theo `id` do app sinh**: chọn lại trên cùng ảnh thì cập nhật cùng một dòng; người khác dùng trùng `id` thì 409. Chữ làm sạch ≤ 60 ký tự, `correctWordId` lạ bị bỏ, tối đa **100 góp ý mới/ngày/tài khoản** (quá thì 429) |

Thân yêu cầu: `id`, `predictedLabel`, `predictedProbability`, `top3[{label, probability}]`, `correctWordId`, `correctText`, `source` (`top3` hoặc `typed`), `modelSource`, `vocabVersion`. **Không có trường ảnh.** Token: bé ở chế độ bé thì dùng token bé, ngược lại dùng token phụ huynh. Xoá tài khoản thì xoá góp ý (cascade).

### A3.9 Khu quản trị (token Admin; mọi API dưới `/api/admin/...`)

| Nhóm | API | Việc |
|---|---|---|
| Thống kê | `GET /api/admin/stats` | Số liệu tổng, đếm trên bản đã xuất bản |
| Người dùng | `GET/POST /api/admin/users`, `GET/PUT/DELETE /api/admin/users/{id}` | Quản lý tài khoản |
| Từ vựng | `GET/POST /api/admin/words`, `GET/PUT/DELETE /api/admin/words/{id}`, `POST …/{id}/restore` | Admin sửa **bản nháp**; xoá mềm, khôi phục được |
| Chủ đề | `GET/POST /api/admin/categories`, `GET/PUT/DELETE …/{id}`, `POST …/{id}/restore` | |
| Xuất bản | `GET /api/admin/vocab/status`, `GET …/validate`, `POST …/publish`, `GET …/releases`, `GET …/model-labels` | Phải `publish` thì app mới thấy; `label` của từ chỉ được lấy từ `labels.txt` của model |
| Huy hiệu | `GET/POST/PUT/DELETE /api/admin/badges…` | Có API, **app Admin chưa có màn hình** |
| Ảnh/âm thanh | `GET/POST/DELETE /api/admin/media` | Upload ≤ 3 MB. App Admin mới gọi phần liệt kê |
| Góp ý nhận diện | `GET /api/admin/feedback` (lọc), `GET …/summary`, `GET …/export.csv`, `DELETE …/{id}` | CSV dùng `InvariantCulture` để không lệch cột |

### A3.10 Luồng chạy nối nhiều API (để kể khi trả lời)

**Phụ huynh vào lần đầu rồi cho bé chơi:**
`register` → `verify-otp` (nhận JWT Parent) → `POST /api/children` → `PUT /api/children/{id}/settings` (đặt 5 phút) → `POST /api/children/{id}/session` (nhận JWT Child) → máy vào chế độ bé.

**Bé chơi một ván và nhận sao:**
`GET /api/games/match/questions` → bé trả lời trên máy → `POST /api/games/sessions` (chỉ đáp án) → server trả sao/huy hiệu mới → `GET /api/progress/me` đồng bộ lại.

**Chụp vật và học:**
Nhận diện **không gọi API nào** (chạy TFLite trên máy) → ghi `learned`/`scan` vào hàng đợi → `POST /api/progress/events` khi có mạng.

**Nhận diện sai:**
"Không đúng?" → lưu hàng đợi `feedback.outbox` → sau 3 giây `POST /api/feedback/recognition` → Admin đọc ở `GET /api/admin/feedback`.

**Từ vựng mới:**
Admin `PUT /api/admin/words/{id}` (nháp) → `POST /api/admin/vocab/publish` → máy bé `GET /api/pack/manifest.json` thấy bản mới → thông báo → `GET /api/pack/vocab.json` và các file → cài đặt.

**Máy thứ hai của bé:**
Bố mẹ `POST /api/children/{id}/link-code` (mã 8 số, 10 phút) → máy bé `POST /api/auth/child-link` → token Child → `GET /api/child/me` + `GET /api/progress/me` (tiến độ gộp).

### A3.11 Gợi ý cho buổi demo: mở Swagger song song

Nếu thầy/cô hỏi "API đâu", C mở `<host>/swagger` sẵn trên laptop (nhớ làm nóng trước, host nguội mất khoảng 11 giây). Có thể minh hoạ nhanh: `GET /health` (sống), `GET /api/vocab/version` (công khai, không cần token), và `POST /api/feedback/recognition` không token trả **401** (chứng minh có xác thực). Đã kiểm chứng trên host: Swagger có 56 đường dẫn và các endpoint góp ý trả 401 khi không có token.

---

## B. Kịch bản demo 7 phút

Nguyên tắc: **đi từ thứ xịn nhất trước**, nếu bị cắt giờ thì vẫn còn những phần quan trọng nhất. Mỗi phần có "nếu hết giờ thì bỏ".

Chuẩn bị sẵn (xem mục D): máy chính đã đăng nhập phụ huynh sẵn và đã có hồ sơ bé; máy phụ sẵn sàng nhập mã; vật thật đặt trên bàn.

| Phút | Phần | Ai làm | Nội dung |
|---|---|---|---|
| 0:00–0:30 | Mở đầu | Bạn (T) | Nêu vấn đề, giới thiệu sản phẩm |
| 0:30–2:30 | **1. Chụp & Học** (xịn nhất) | T nói, A cầm máy | Nhận diện thật, phát âm, góp ý |
| 2:30–3:30 | **2. Game + sao + huy hiệu** | A | Nghe & chọn hình / Tìm vật |
| 3:30–4:30 | **3. Bố mẹ: giới hạn giờ + dashboard** | B | Khoá máy, mở bằng phép nhân, dashboard |
| 4:30–5:30 | **4. Từ vựng mới tự báo** | C | Xuất bản, thông báo, bấm cập nhật |
| 5:30–6:15 | **5. Nhiều máy + offline** | A + B | Mã liên kết, máy thứ hai |
| 6:15–7:00 | **6. Kiến trúc, kiểm thử, kết** | T | Số liệu, bảo mật, hạn chế thật thà |

### 0:00–0:30 Mở đầu (T)
**Nói:** "Trẻ học từ vựng tiếng Anh thường chán vì từ nằm trên giấy, không gắn với đồ vật quanh em. English Cam cho bé **chụp một đồ vật**, app tự nhận ra và đọc tên tiếng Anh. Mô hình AI chạy ngay trên điện thoại nên ảnh của bé không rời máy. Bố mẹ quản lý giờ chơi và theo dõi tiến độ qua tài khoản."
**Màn hình:** Home của bé (máy chính).

### 0:30–2:30 Phần 1 — Chụp & Học (2 phút)
**Thao tác (A cầm máy, T nói):**
1. Home → **Chụp & Học** → hướng camera vào **cup** → Chụp ảnh → Xong. Chờ kết quả (khoảng vài giây).
2. Kết quả hiện "cup / cái cốc", nghe phát âm, Cam nói. **Nói:** "Model MobileNetV2 tự huấn luyện, 24 lớp, độ chính xác 88,84% trên tập test. Chạy hoàn toàn offline. Chỉ hiện khi tin chắc từ 70% trở lên."
3. Chụp tiếp một vật thứ hai (**banana** hoặc **ball**), chỉ lướt qua.
4. **Cho thấy lúc sai:** chụp vật mà model hay sai hoặc bấm **Không đúng?** trên một kết quả → chọn **Khác…** → gõ "cái bàn" → Gửi → lời cảm ơn của Cam.
**Nói:** "Khi nhận sai, bé tự sửa. App gửi **chỉ chữ** lên server, không bao giờ gửi ảnh. Đây là dữ liệu để cải thiện model sau."
**Nếu hết giờ:** bỏ vật thứ hai, giữ phần góp ý (đây là điểm khác biệt).

### 2:30–3:30 Phần 2 — Game (1 phút)
**Thao tác (A):** Home → **Chơi** → **Nghe & chọn hình**: chơi 2–3 câu, chọn sai một câu để thấy phản hồi, tới tổng kết sao/huy hiệu. Nếu còn thời gian, mở **Tìm vật** và chụp một vật đúng với từ được nêu.
**Nói:** "Sao và huy hiệu do **server tính**, app chỉ gửi đáp án, nên không gian lận được. Câu hỏi lấy từ server, offline thì tự tạo."
**Nếu hết giờ:** chỉ làm Nghe & chọn hình, bỏ Tìm vật.

### 3:30–4:30 Phần 3 — Phụ huynh: giờ chơi + dashboard (1 phút)
**Thao tác (B):**
1. Nếu đã đặt giới hạn nhỏ từ trước: cho thấy **màn hết giờ** (hoặc bật qua máy phụ). Bấm **Dành cho bố mẹ** → giải phép nhân → chọn **10 phút** → mở khoá.
2. Chuyển sang phụ huynh → Cài đặt → **Tiến độ** của bé: chỉ vào từ đã học, độ chính xác, chủ đề, huy hiệu, nút chép CSV.
**Nói:** "Máy tự khoá khi hết giờ, đè lên mọi màn. Muốn chơi thêm phải qua cổng bố mẹ. Phần vượt hiện ở dashboard. Dữ liệu dashboard tính ở server và chỉ phụ huynh sở hữu bé mới xem được."
**Lưu ý:** không chờ 5 phút thật trên sân khấu. Dùng cấu hình sẵn (mục D).

### 4:30–5:30 Phần 4 — Từ vựng mới tự báo (1 phút)
**Thao tác (C, ở laptop + máy chính):**
1. Ở Admin (backend local): sửa/đổi một từ hoặc ghi chú → **Xuất bản** (bản N+1).
2. Trên máy chính, hiện thông báo "có từ vựng mới" → Cài đặt (cổng phép nhân) → **Cập nhật từ vựng** → **Cập nhật ngay (bản N)** → thanh tiến trình → "Đã cập nhật lên bản N".
**Nói:** "Không phải nhập link. Admin xuất bản, máy của bé tự báo. Gói được kiểm tra sha256, hỏng thì tự về bản đóng gói sẵn."
**Nếu không có Admin chạy được:** dùng ảnh `docs/demo/39-admin-xuat-ban.png`, `41-thong-bao-tu-vung-moi.png`, `42-man-cap-nhat-co-ban-moi.png`, `43-cap-nhat-xong.png` (xem mục D).

### 5:30–6:15 Phần 5 — Nhiều máy + offline (45 giây)
**Thao tác (A + B):** B tạo **mã liên kết** (Hồ sơ của bé → Quản lý → "Thêm máy cho bé") → A nhập mã trên **máy thứ hai** → cho thấy cùng bé, cùng tiến độ. Bật chế độ máy bay một giây, vào Từ vựng, cho thấy học vẫn chạy.
**Nói:** "App offline-first: ghi vào máy trước, có mạng thì tự gửi bù. Hai máy cùng một bé thì tiến độ hợp nhất."

### 6:15–7:00 Phần 6 — Kiến trúc và kết (T)
**Slide hoặc sơ đồ phần A.** Nói theo thứ tự:
1. "Flutter + TFLite trên máy, ASP.NET Core 8 + SQL Server ở server."
2. "**299 test** phía app, **149 test** phía backend chạy API thật trên SQL Server."
3. "Bảo mật: JWT, 3 vai trò, kiểm tra quyền sở hữu bé (chống IDOR), ảnh không rời máy, release bắt buộc https."
4. **Thật thà về hạn chế:** "Model 24 lớp nên có vật nhận sai; apple và table còn yếu; đó là lý do có vòng góp ý. Chưa làm: thông báo đẩy khi app đóng, đăng nhập Google chưa kiểm chứng."
5. "Cảm ơn thầy/cô, mời đặt câu hỏi."

---

## C. Phân vai gợi ý (3 thành viên hỗ trợ)

Tên "A, B, C" chỉ là vai trò; gán người thật theo sở trường.

| Vai | Phụ trách | Thiết bị | Việc cụ thể |
|---|---|---|---|
| **T — Thuyết trình (bạn)** | Nói chính, giữ nhịp 7 phút | Không cầm máy | Mở đầu, lời dẫn từng phần, phần kết, trả lời hỏi đáp |
| **A — Máy của bé** | Thao tác ứng dụng trên máy chính | Điện thoại chính (cắm màn chiếu) | Chụp & Học, game, nhập mã liên kết trên máy phụ |
| **B — Phụ huynh** | Phần của bố mẹ | Điện thoại hoặc máy phụ | Giới hạn giờ, cổng phép nhân, dashboard, tạo mã liên kết |
| **C — Kỹ thuật / dự phòng** | Admin, host, hình dự phòng | Laptop | Xuất bản từ vựng, theo dõi host/OTP, giữ ảnh dự phòng, bấm giờ |

Quy ước: C giơ tay hoặc nhắn ở phút 3:30 và 5:30 nếu T chậm quá 15 giây. T không chờ thao tác quá 10 giây; nếu kẹt, nói "mình có ảnh minh hoạ" và C chuyển sang ảnh dự phòng.

---

## D. Chuẩn bị, dự phòng, hỏi đáp

### D1. Trước giờ demo (khoảng 30 phút)
- [ ] **Cài APK release** (`build/app/outputs/flutter-apk/app-release.apk`, 84 MB) lên **đúng chiếc điện thoại sẽ demo**. Chạy thử toàn bộ luồng, **đặc biệt camera thật**: chưa kiểm chứng APK release trên máy Android thật.
- [ ] **Thử nhận diện bằng vật thật** ít nhất 10 lần mỗi vật: cup, bottle, book, banana, ball, teddy_bear. Chọn vật nào ra đúng ổn định nhất, ánh sáng đủ, nền gọn.
- [ ] **Làm nóng host** trước 5 phút: mở `/health` hoặc Swagger (host khởi động nguội mất khoảng 11 giây).
- [ ] **Tạo sẵn tài khoản phụ huynh + hồ sơ bé** để không phải chờ OTP trên sân khấu. Đã đăng nhập sẵn trên máy chính.
- [ ] **OTP:** nếu bắt buộc demo đăng ký, chỉ bấm "gửi mã" **một lần** (mã cũ bị vô hiệu khi gửi mã mới); mở Gmail sẵn. Trên Android có khung SMS-autofill "Waiting for message" có thể che ô nhập, bấm CANCEL.
- [ ] **Đặt sẵn giới hạn giờ nhỏ** (ví dụ 5 phút) và để bé đã dùng gần hết trước giờ demo, hoặc dùng máy phụ để cho thấy khoá nhanh.
- [ ] **Máy phụ** (cho phần liên kết): chưa đăng nhập, ở màn chào, sẵn sàng nhập mã.
- [ ] **Admin:** chạy backend local (`docker compose up -d`, `dotnet run --no-launch-profile --urls http://0.0.0.0:5080`), đăng nhập tài khoản Admin; hoặc dùng ảnh dự phòng. Máy chính phải trỏ đúng backend (cùng mạng LAN) nếu demo cập nhật từ vựng bằng backend local.
- [ ] Sạc đầy pin, tắt thông báo, chế độ không làm phiền, tắt khoá xoay, độ sáng cao.
- [ ] Quay sẵn **video 7 phút** chạy toàn bộ luồng và đặt ảnh `docs/demo/*.png` trong một thư mục dễ mở.
- [ ] Hẹn giờ: tập **ít nhất 2 lần** đúng 7 phút.

### D2. Nếu có sự cố
| Sự cố | Xử lý |
|---|---|
| Nhận diện ra "chưa chắc" hoặc sai nhiều | Đổi sang vật khác đã tập; nói thẳng "đây là lúc cần nút Không đúng?" rồi chuyển sang phần góp ý |
| Mất mạng / host chậm | Nói đây là offline-first, tiếp tục Chụp & Học và Từ vựng (không cần mạng); phần cần server dùng ảnh dự phòng |
| OTP không tới | Dùng máy đã đăng nhập sẵn; không đăng ký trực tiếp |
| Màn khoá hết giờ không xuất hiện | C mở ảnh `21-het-gio-choi.png`, `22-cho-choi-them.png`, `23-mo-khoa.png` |
| Admin không chạy | Dùng `39-admin-xuat-ban.png` → `41-…` → `42-…` → `43-…` |
| App crash | Mở lại app (phiên vẫn còn, không phải đăng nhập lại); nếu vẫn lỗi, chiếu video quay sẵn |

### D3. Những chỗ **chưa kiểm chứng** (nếu bị hỏi, trả lời thật)
- Google Sign-In (cần Android OAuth client + SHA-1).
- Khu Admin **trên host** (host chỉ có phụ huynh và bé; Admin đã chạy ở backend local).
- APK release trên điện thoại Android thật và nhận diện trên iPhone thật (bản trên iPhone là bản cũ).
- Phát âm nghe rõ trên loa máy thật.
- Thông báo đẩy khi app đã đóng (chưa làm, cần FCM).

### D4. Câu hỏi thầy/cô có thể hỏi
| Câu hỏi | Trả lời ngắn |
|---|---|
| Model huấn luyện thế nào? | MobileNetV2 pretrained ImageNet, 2 giai đoạn (đóng băng backbone rồi fine-tune 30 lớp cuối). Dữ liệu: ảnh tự chụp của nhóm (test chỉ gồm ảnh tự chụp, chia theo khối để không rò rỉ) + ảnh công khai (train/val). Test accuracy 88,84% trên 645 ảnh. |
| Sao chỉ 24 lớp? | Giới hạn thời gian thu ảnh. Lớp `none` chưa có ảnh nên dùng ngưỡng 0,7 để nói "chưa nhận ra". |
| Bé có bị lộ ảnh không? | Không. Ảnh chỉ xử lý trên máy. Góp ý chỉ gửi chữ. Có quy tắc cứng và test kiểm tra thân yêu cầu không chứa ảnh. |
| Chống gian lận sao/huy hiệu? | Server tính, app chỉ gửi đáp án; ván có `id` nên gửi lại không bị cộng đôi. |
| Mất mạng thì sao? | Ghi vào hàng đợi bền trên máy và gửi bù khi có mạng; học và chụp vẫn chạy offline. |
| Hai bé dùng chung máy? | Mỗi hồ sơ có ngăn lưu riêng. |
| Bảo mật tài khoản? | JWT lưu `flutter_secure_storage`, OTP qua email, 3 vai trò, kiểm tra quyền sở hữu bé ở mọi endpoint `{childId}`, release bắt buộc https. |
| Có test không? | App 299 test, backend 149 test chạy API thật trên SQL Server; `flutter analyze` sạch. |
| Hạn chế? | Model nhận sai một số vật (apple, table); chưa có thông báo đẩy; Google Sign-In chưa kiểm chứng; khoá giờ do app thực thi nên không chống được người cố tình gỡ app. |

### D5. Tài liệu liên quan
- `docs/demo.md` — kịch bản demo chi tiết có ảnh chụp màn hình.
- `docs/BACKEND_PLAN.md`, `docs/VOCAB_PACK.md`, `docs/TEST_REPORT.md` (lưu ý: còn ghi "46 test", đã cũ).
- `../reports/classification_report.txt` — độ chính xác và recall từng lớp.
