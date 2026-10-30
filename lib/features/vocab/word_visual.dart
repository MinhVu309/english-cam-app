import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/pack/pack_store.dart';
import '../../data/vocab_word.dart';

/// Hình minh hoạ của một từ: ảnh (đóng gói sẵn theo mã từ, hoặc của gói cập nhật) > emoji > chữ cái đầu.
class WordVisual extends StatelessWidget {
  const WordVisual({super.key, required this.word, required this.size});

  final VocabWord word;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = word.image;
    final emoji = word.emoji;
    Widget letter() => Text(
      word.en.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: size * 0.6,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    final Widget child;
    if (image != null) {
      Widget errorBuilder(BuildContext c, Object e, StackTrace? s) => letter();
      // Ảnh thật cắt tròn như avatar: khớp với vòng tròn trắng phía sau thẻ từ và che nền xám nhạt của vài ảnh gốc
      // (ảnh đã được chuẩn hoá thành ô vuông, nên cover chỉ cắt bốn góc). Emoji và chữ cái không cần.
      Widget framed(Widget img) => ClipOval(child: img);
      if (PackStore.isBundled(image)) {
        child = framed(
          Image.asset(
            image,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: errorBuilder,
          ),
        );
      } else {
        final packed = PackStore.instance?.fileFor(image);
        child = packed == null
            ? letter()
            : framed(
                Image.file(
                  File(packed.path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: errorBuilder,
                ),
              );
      }
    } else if (emoji != null) {
      child = Text(emoji, style: TextStyle(fontSize: size * 0.7, height: 1));
    } else {
      child = letter();
    }
    return SizedBox.square(
      dimension: size,
      child: Center(child: ExcludeSemantics(child: child)),
    );
  }
}
