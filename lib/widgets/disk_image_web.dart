import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:granthprabandhan/compat/io.dart';

Widget paintFile(
  File file, {
  double? width,
  double? height,
  BoxFit? fit,
  Alignment alignment = Alignment.center,
  bool gaplessPlayback = false,
  int? cacheWidth,
  ImageFrameBuilder? frameBuilder,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return FutureBuilder<Uint8List>(
    future: file.readAsBytes(),
    builder: (context, snap) {
      if (!snap.hasData) {
        if (snap.hasError && errorBuilder != null) {
          return errorBuilder(context, snap.error ?? 'empty', snap.stackTrace ?? StackTrace.empty);
        }
        return const SizedBox.shrink();
      }
      return Image.memory(
        snap.data!,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: gaplessPlayback,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      );
    },
  );
}
