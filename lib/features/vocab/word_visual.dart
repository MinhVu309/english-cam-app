import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/pack/pack_store.dart';
import '../../data/vocab_word.dart';

/// Hình minh hoạ của một từ: ảnh asset > emoji > chữ cái đầu.
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
      final packed = PackStore.isBundled(image)
          ? null
          : PackStore.instance?.fileFor(image);
      child = PackStore.isBundled(image)
          ? Image.asset(
              image,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: errorBuilder,
            )
          : packed == null
          ? letter()
          : Image.file(
              File(packed.path),
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: errorBuilder,
            );
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
