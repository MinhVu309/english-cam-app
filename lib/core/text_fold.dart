const Map<String, String> _vietnamese = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final Map<String, String> _foldMap = {
  for (final e in _vietnamese.entries)
    for (final ch in e.value.split('')) ch: e.key,
};

/// Chữ thường, bỏ dấu tiếng Việt, gộp khoảng trắng: để so khớp gợi ý ("cai ban" khớp "cái bàn", "Table" khớp "table").
String foldText(String input) {
  final lower = input.toLowerCase();
  final out = StringBuffer();
  var lastSpace = true;
  for (final ch in lower.split('')) {
    if (ch.trim().isEmpty) {
      if (!lastSpace) out.write(' ');
      lastSpace = true;
    } else {
      out.write(_foldMap[ch] ?? ch);
      lastSpace = false;
    }
  }
  return out.toString().trim();
}
