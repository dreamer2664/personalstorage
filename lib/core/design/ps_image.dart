import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'theme.dart';

/// Shows an image from a local file (mobile) or a blob/http URL (web), with a soft placeholder
/// while loading and a neutral tile when the file is gone.
class PsImage extends StatelessWidget {
  const PsImage(this.path, {this.fit = BoxFit.cover, this.cacheWidth, super.key});

  final String path;
  final BoxFit fit;

  /// Decode at this pixel width to keep thumbnails cheap in memory.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    Widget broken() => ColoredBox(color: ps.separator, child: Center(child: Icon(CupertinoIcons.photo, color: ps.tertiaryLabel)));
    final isUrl = kIsWeb || path.startsWith('http') || path.startsWith('blob:');
    final image = isUrl
        ? Image.network(path, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => broken())
        : Image.file(File(path), fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => broken());
    return image;
  }
}
