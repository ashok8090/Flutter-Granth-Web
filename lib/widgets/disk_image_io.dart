import 'dart:io';

import 'package:flutter/material.dart';

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
  return Image.file(
    file,
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: gaplessPlayback,
    cacheWidth: cacheWidth,
    frameBuilder: frameBuilder,
    errorBuilder: errorBuilder,
  );
}
