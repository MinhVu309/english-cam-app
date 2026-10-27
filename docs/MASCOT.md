# Cam — linh vật của English Cam

> Tài liệu về nhân vật **Cam**: thiết kế, cách Cam xuất hiện trong app, cách thêm lời nhắn, và các file liên quan.

## 1. Cam là ai?

**Cam** là một quả cam tròn, có cuống với hai chiếc lá xanh trên đầu, đôi mắt to long lanh, má hồng, hai tay và hai chân nhỏ xíu. Tên "Cam" vừa là màu cam của app, vừa là nghĩa tiếng Việt của từ **orange** (một trong 24 từ bé học). Cam là người bạn nhỏ đi cùng bé trong mọi chức năng: chào bé, nhắc bé cách dùng, khen khi bé làm đúng và động viên khi bé sai.

- **Tính cách:** thân thiện, vui vẻ, hay khen, không bao giờ trách bé.
- **Cách xưng hô:** Cam xưng "Cam" hoặc "mình", gọi người dùng là "bé".
- **Bản quyền:** Cam do nhóm **tự vẽ bằng code** (`CustomPaint`), không dựa trên nhân vật có bản quyền nào.

## 2. Biểu cảm

Cam có 4 biểu cảm (`MascotMood` trong [mascot.dart](../lib/features/mascot/mascot.dart)):

| Biểu cảm | Hình dạng & điệu bộ | Dùng khi |
|---|---|---|
| `happy` | Mắt tròn đảo nhìn quanh, miệng cười, hai tay đung đưa, người lắc lư nhẹ | Mặc định, chào hỏi, hướng dẫn |
| `cheer` | Mắt cười `^ ^`, miệng mở to có lưỡi, **nhảy cẫng** (co giãn khi bật/tiếp đất), hai tay giơ cao vẫy, 4 ngôi sao ✨ lấp lánh xoay | Bé làm đúng, xong ván, được huy hiệu |
| `thinking` | Nghiêng đầu, một bên lông mày nhướn, mắt nhìn lên, **tay chống cằm gõ gõ**, 3 bong bóng suy nghĩ nhấp nháy | Chưa chắc, danh sách trống, gợi ý |
| `oops` | Mắt to đồng tử nhỏ, lông mày lo lắng, miệng "ồ", **hai tay giơ lên**, lắc nhẹ, giọt mồ hôi trượt xuống | Bé chọn sai, có lỗi — vẫn thân thiện, không buồn |

### Hoạt hình (chạy liên tục, không có điểm "giật" khi lặp)

| Chuyển động | Chi tiết |
|---|---|
| Thở | Thân co giãn nhẹ (squash & stretch) chu kỳ 2,6 giây |
| Lá | Đung đưa quanh cuống; nảy theo khi Cam nhảy hoặc bị chạm |
| Chớp mắt | Mỗi 3,8 giây, cứ 3 lần có 1 lần chớp đúp; mỗi Cam lệch pha nên nhiều Cam không chớp cùng lúc |
| Nói | Khi có câu thoại mới, Cam **nhép miệng ~1,5 giây** (tham số `talkKey`) |
| Chạm | Chạm vào Cam → Cam nảy "boing" (không chặn nút bấm bên ngoài) |
| Đổi biểu cảm | Cam nhún một cái, đổi mặt ở giữa cú nhún; phụ kiện (sao, mồ hôi…) mờ dần vào |

Hoạt hình tự tắt khi hệ thống bật **"giảm chuyển động"** (accessibility): Cam đứng yên ở tư thế chuẩn. Toàn bộ chuyển động dùng một `Ticker` + `RepaintBoundary` nên chỉ vẽ lại vùng của Cam, và tự dừng khi màn hình bị che (TickerMode).

## 3. Cam xuất hiện ở đâu?

### 3.1. Cam "đồng hành" — lâu lâu hiện ra nhắn bé

Mọi màn hình chính được bọc bởi `MascotHost` ([mascot_host.dart](../lib/features/mascot/mascot_host.dart)). Cam **không chiếm chỗ cố định**: Cam trượt ra một góc, hiện bong bóng lời thoại, rồi tự rút đi.

- **Cách hiện:** Cam trượt ra từ góc rồi nảy "boing", bong bóng bật ra sau ~0,16 giây từ phía đuôi, chữ hiện theo ngay sau.
- **Lần đầu hiện:** khoảng 9 giây sau khi bé vào màn hình.
- **Ở lại:** 7 giây, sau đó tự rút.
- **Lần sau:** cách nhau ngẫu nhiên 24–42 giây.
- **Chạm vào Cam:** Cam nói một câu khác ngay (không lặp lại câu vừa nói) — Cam **ở yên tại chỗ**, nhún, đổi mặt, nhép miệng và bong bóng bật lại; máy rung nhẹ (haptic).
- Mỗi lần Cam nói có một tiếng "tap" nhẹ.

| Màn hình | `contextKey` | Góc xuất hiện |
|---|---|---|
| Camera | `camera` | Trên-phải (dưới thanh tiêu đề, tránh nút chụp) |
| Kết quả nhận diện | `result` | Dưới-phải |
| Danh sách từ vựng | `vocab` | Dưới-phải |
| Chi tiết từ | `vocab_detail` | Dưới-phải |
| Màn Chơi (chọn game) | `hub` | Dưới-phải |
| Game Nghe & chọn hình | `match` | Dưới-phải |
| Game Tìm vật | `hunt` | Dưới-**trái** (tránh nút Chụp ảnh) |

### 3.2. Màn hình chính — Cam luôn có mặt

Ở Home, Cam đứng cạnh một bong bóng lời nhắn cố định (`MascotStrip`). Câu nhắn tự đổi mỗi **14 giây** hoặc khi bé chạm vào Cam; mỗi lần đổi, bong bóng bật lại và co giãn chiều cao mượt (`AnimatedSize`), Cam nhép miệng nói.

### 3.3. Cam trong các trạng thái

Cam cũng thay các biểu tượng khô khan ở những tình huống đặc biệt:

| Tình huống | Biểu cảm |
|---|---|
| Onboarding 3 bước | `happy` → `thinking` → `cheer` |
| Game ghép: đang nghe / chọn sai / chọn đúng | `happy` / `oops` / `cheer` |
| Game ghép: tổng kết ván | `cheer` (to) + pháo giấy |
| Game tìm vật: tìm đúng / chưa đúng | `cheer` / `oops` |
| Kết quả: model chưa chắc | `thinking` |
| Kết quả: có lỗi | `oops` |
| Danh sách từ trống (tìm không thấy) | `thinking` |
| Camera: chưa cấp quyền / không có camera / lỗi | `thinking` / `oops` / `oops` |
| Không nạp được dữ liệu lúc mở app | `oops` (to) + nút "Thử lại" |
| Cài đặt → Giới thiệu | `happy` |

## 4. Lời nhắn của Cam

### 4.1. File dữ liệu

Toàn bộ câu nhắn nằm trong [assets/mascot/messages.json](../assets/mascot/messages.json) — **sửa lời nhắn không cần đụng code**. Cấu trúc:

```json
{
  "home": [
    { "text": "Chào bé! Hôm nay mình học gì nhỉ?", "mood": "happy" },
    { "text": "Bé đã học {learned} từ rồi, giỏi quá!", "when": "has_learned", "mood": "cheer" }
  ],
  "camera": [ { "text": "Chỗ đủ sáng thì Cam nhìn rõ hơn đó!" } ]
}
```

| Trường | Ý nghĩa |
|---|---|
| khoá ngoài cùng | Tên màn hình (`contextKey`): `home`, `camera`, `result`, `vocab`, `vocab_detail`, `hub`, `match`, `hunt` |
| `text` | Nội dung câu nói, **tối đa 60 ký tự** |
| `mood` | `happy` (mặc định), `cheer`, `thinking`, `oops` |
| `when` | Điều kiện để câu được chọn (xem dưới); bỏ trống = luôn được |

**Điều kiện `when`:**

| Giá trị | Chỉ chọn câu này khi… |
|---|---|
| `any` | luôn luôn |
| `no_learned` | bé chưa học từ nào |
| `has_learned` | bé đã học ít nhất 1 từ |
| `has_stars` | bé đã có ít nhất 1 sao |

**Biến điền sẵn trong `text`:** `{learned}` (số từ đã học), `{stars}` (số sao), `{total}` (tổng số từ).

### 4.2. Cách chọn câu

`MascotMessages.pick` ([mascot_messages.dart](../lib/features/mascot/mascot_messages.dart)):

1. Lấy các câu của màn hình hiện tại.
2. Giữ lại câu có điều kiện `when` đang đúng.
3. Bỏ câu vừa nói (để không lặp liên tiếp), nếu còn câu khác.
4. Chọn ngẫu nhiên một câu, điền biến.

Nếu không có câu phù hợp (hoặc chưa nạp được file), Cam **im lặng** chứ không gây lỗi.

### 4.3. Thêm lời nhắn mới

1. Mở `assets/mascot/messages.json`, thêm một mục vào đúng màn hình.
2. Giữ câu **ngắn (≤ 60 ký tự)**, giọng vui, xưng "Cam/mình" và gọi "bé".
3. Chạy `dart run tool/check_assets.dart` để kiểm tra: mỗi màn hình cần **≥ 3 câu**, điều kiện `when` hợp lệ, không câu nào rỗng hoặc quá dài.
4. Chạy `flutter test` — bộ test kiểm tra thêm là không còn `{biến}` chưa điền.

### 4.4. Thêm màn hình mới cho Cam

Bọc màn hình bằng `MascotHost`:

```dart
return MascotHost(
  contextKey: 'ten_man_hinh',        // thêm khoá này vào messages.json
  alignment: Alignment.bottomRight,  // góc Cam hiện ra
  child: Scaffold(...),
);
```

Nhớ thêm `ten_man_hinh` vào `messages.json` (và vào danh sách `screens` trong `tool/check_assets.dart`).

## 5. Dành cho bố mẹ

- **Tắt/bật lời nhắn:** Cài đặt (sau cổng phụ huynh) → công tắc **"Cam nhắn tin cho bé"**. Tắt thì Cam không tự hiện nữa (Cam ở các trạng thái như onboarding hay game vẫn xuất hiện bình thường). Lựa chọn được lưu trên máy (khoá `mascot_chatter`) và có hiệu lực ngay, kể cả khi Cam đang hiện.
- **Quyền riêng tư:** lời nhắn chỉ dùng số liệu cục bộ trên máy (số từ đã học, số sao); không gửi đi đâu.

## 6. Thiết kế hình ảnh

Cam được vẽ bằng `MascotPainter` ([mascot.dart](../lib/features/mascot/mascot.dart)) trên canvas vuông, gồm:

| Phần | Chi tiết |
|---|---|
| Thân | Hình tròn, gradient tròn `#FFC27A → #FF9F43 → #F07A12`, đáy tối dần cho có khối, lỗ chân lông vỏ cam (khi Cam ≥ 80dp), ánh phản chiếu viền dưới, vệt bóng loáng góc trái trên, viền mảnh `#D9620A` |
| Lá & cuống | Cuống nâu `#6D4C41` cong nhẹ, một lá lớn + một lá nhỏ gradient `#8BE08E → #2E9E46`, có gân sáng |
| Mắt | Tròng trắng viền nâu, đồng tử gradient nâu `#8A5530 → #3B2210`, mí trên hơi tối, **hai chấm sáng** long lanh |
| Lông mày | Có ở mọi biểu cảm, dáng thay đổi theo cảm xúc |
| Miệng | Cười (happy), chữ D có lưỡi (cheer / khi nói), tròn nhỏ (thinking), "ồ" (oops) |
| Má | Má hồng gradient mềm `#FF5E62`, đậm hơn khi `cheer` |
| Tay & chân | Tay tròn `#F08A2B` viền `#D9620A`, bàn tay `#FFAE57`; hai bàn chân `#D9620A` |
| Bóng | Elip mờ (blur) dưới chân; nhỏ và nhạt đi khi Cam nhảy lên |
| Phụ kiện theo biểu cảm | Sao vàng lấp lánh xoay (`cheer`), bong bóng suy nghĩ (`thinking`), giọt mồ hôi xanh trượt (`oops`) |

Bong bóng lời thoại ([speech_bubble.dart](../lib/features/mascot/speech_bubble.dart)): nền gradient trắng → kem `#FFF3E3`, viền cam nhạt, bo tròn 24, đuôi liền khối (`Path.combine`) chỉ về phía Cam, bóng đổ nâu nhạt; chữ **18sp**, đậm (w800), phông Nunito. Khi hiện hoặc đổi câu: bật ra từ phía đuôi với độ nảy đàn hồi (`ElasticOutCurve`), chữ trượt lên và hiện dần. Tham số `delay` cho bong bóng xuất hiện sau Cam.

## 7. Khả năng tiếp cận

- Cam và bong bóng được khai báo là **vùng cập nhật trực tiếp** (`liveRegion`) cho trình đọc màn hình: "Cam nói: …". Hình Cam trang trí không bị đọc lặp.
- Tôn trọng chế độ **giảm chuyển động**: Cam đứng yên, không nhún, không chớp, không nhép miệng; bong bóng hiện ngay không nảy.
- Chữ trong bong bóng ≥ 18sp; vùng chạm vào Cam đủ lớn (Cam rộng ≥ 76dp).

## 8. Bản đồ file

| File | Vai trò |
|---|---|
| `lib/features/mascot/mascot.dart` | Widget `Mascot` (tham số `mood`, `size`, `animate`, `talkKey`, `reactToTouch`), `MascotMood`, bộ vẽ `MascotPainter(mood, t, poke:, talk:, accessory:)` — `t` tính bằng giây |
| `lib/features/mascot/speech_bubble.dart` | Bong bóng lời thoại |
| `lib/features/mascot/mascot_host.dart` | `MascotHost` (Cam tự hiện) và `MascotStrip` (dải Cam ở Home) |
| `lib/features/mascot/mascot_messages.dart` | Nạp và chọn lời nhắn, điền biến, điều kiện |
| `assets/mascot/messages.json` | Kho lời nhắn |
| `lib/services/app_settings.dart` | Lưu công tắc `mascotChatter` |
| `lib/features/settings/settings_screen.dart` | Công tắc "Cam nhắn tin cho bé" |
| `test/mascot_companion_test.dart` | Test kho lời nhắn, lịch tự hiện/rút, chạm đổi câu, tắt nhắn tin |
| `tool/check_assets.dart` | Kiểm tra `messages.json` |

## 9. Kiểm thử

Chạy `flutter test`. Các test liên quan Cam:

- Mọi màn hình đều có ≥ 3 câu, không câu nào dài quá 60 ký tự, không còn `{biến}` chưa điền.
- Điều kiện `when`: bé chưa học thì Cam không khoe "đã học … từ".
- Không nhắc lại đúng câu vừa nói; context lạ không gây lỗi.
- Cam tự hiện sau thời gian chờ, tự rút, rồi hẹn lần sau; chạm vào Cam đổi câu.
- Tắt "Cam nhắn tin" thì Cam im lặng, kể cả khi đang hiện.
- Cả 4 biểu cảm vẽ được ở nhiều kích cỡ mà không lỗi.

> Trong test, `Mascot.animationsEnabled` và `MascotHost.autoEnabled` được tắt sẵn (xem `test/flutter_test_config.dart`) để không có timer hay hoạt hình lặp làm treo `pumpAndSettle`.
