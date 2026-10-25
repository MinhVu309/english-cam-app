import 'package:flutter/material.dart';

/// Bảng màu của app. Chữ trắng trên các màu nút lớn đều đạt tương phản >= 3:1
/// (chuẩn WCAG cho chữ lớn); chữ tối trên nền kem đạt > 15:1.
abstract final class Palette {
  static const cream = Color(0xFFFFF8EE); // nền
  static const ink = Color(0xFF2B1B12); // chữ chính
  static const inkSoft = Color(
    0xFF6B5B52,
  ); // chữ phụ (tương phản 5.7:1 trên trắng)

  static const orange = Color(0xFFE8590C); // Chụp & Học, nút chính
  static const teal = Color(0xFF1F8A7A); // Từ vựng
  static const purple = Color(0xFF6A5AD0); // Chơi

  static const peel = Color(0xFFFF9F43); // thân mascot / điểm nhấn
  static const leaf = Color(0xFF4CAF50);
  static const star = Color(0xFFFFC107);

  static const good = Color(0xFFBFE8C8); // đáp án đúng
  static const oops = Color(0xFFFFE0CC); // đáp án sai (nhẹ nhàng)
}
