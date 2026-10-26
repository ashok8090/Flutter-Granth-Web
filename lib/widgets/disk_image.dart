import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:granthprabandhan/compat/io.dart';

import 'disk_image_io.dart' if (dart.library.html) 'disk_image_web.dart' as impl;

class DiskImage extends StatelessWidget {
  const DiskImage(
    this.file, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.gaplessPlayback = false,
    this.cacheWidth,
    this.frameBuilder,
    this.errorBuilder,
  });

  final File file;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final bool gaplessPlayback;
  final int? cacheWidth;
  final ImageFrameBuilder? frameBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return impl.paintFile(
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
}
