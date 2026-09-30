import 'package:flutter/cupertino.dart';

import 'ps_image.dart';
import 'tokens.dart';

/// Photo collage with rounded tiles: 1 -> hero, 2 -> split, 3 -> hero + two, 4+ -> grid with a
/// "+N" overlay. Used in note cards (compact) and on the detail screen (full width).
class PhotoCollage extends StatelessWidget {
  const PhotoCollage({required this.paths, this.height = 180, this.radius = 18, this.onTap, this.cacheWidth, super.key});

  final List<String> paths;
  final double height;
  final double radius;
  final ValueChanged<int>? onTap;
  final int? cacheWidth;

  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: squircle(radius)),
        child: _layout(context),
      ),
    );
  }

  Widget _tile(BuildContext context, int i, {Widget? overlay}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(i),
        child: Stack(fit: StackFit.expand, children: [PsImage(paths[i], cacheWidth: cacheWidth), ?overlay]),
      );

  Widget _layout(BuildContext context) {
    final n = paths.length;
    if (n == 1) return _tile(context, 0);
    if (n == 2) {
      return Row(children: [
        Expanded(child: _tile(context, 0)),
        const SizedBox(width: _gap),
        Expanded(child: _tile(context, 1)),
      ]);
    }
    if (n == 3) {
      return Row(children: [
        Expanded(flex: 3, child: _tile(context, 0)),
        const SizedBox(width: _gap),
        Expanded(
          flex: 2,
          child: Column(children: [
            Expanded(child: _tile(context, 1)),
            const SizedBox(height: _gap),
            Expanded(child: _tile(context, 2)),
          ]),
        ),
      ]);
    }
    final extra = n - 4;
    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: _tile(context, 0)),
          const SizedBox(width: _gap),
          Expanded(child: _tile(context, 1)),
        ]),
      ),
      const SizedBox(height: _gap),
      Expanded(
        child: Row(children: [
          Expanded(child: _tile(context, 2)),
          const SizedBox(width: _gap),
          Expanded(
            child: _tile(
              context,
              3,
              overlay: extra > 0
                  ? ColoredBox(
                      color: const Color(0x99000000),
                      child: Center(child: Text('+$extra', style: PsText.title(const Color(0xFFFFFFFF)))),
                    )
                  : null,
            ),
          ),
        ]),
      ),
    ]);
  }
}
