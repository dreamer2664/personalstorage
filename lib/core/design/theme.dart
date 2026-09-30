import 'package:flutter/cupertino.dart';

import 'tokens.dart';

/// Provides the active [PsPalette] to the tree (resolved from the platform/app brightness).
class PsThemeScope extends StatelessWidget {
  const PsThemeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final palette = brightness == Brightness.dark ? PsPalette.dark : PsPalette.light;
    return _InheritedPalette(palette: palette, child: child);
  }
}

class _InheritedPalette extends InheritedWidget {
  const _InheritedPalette({required this.palette, required super.child});

  final PsPalette palette;

  @override
  bool updateShouldNotify(_InheritedPalette old) => old.palette != palette;
}

extension PsContext on BuildContext {
  /// The Personal Storage palette for the current brightness.
  PsPalette get ps {
    final inherited = dependOnInheritedWidgetOfExactType<_InheritedPalette>();
    if (inherited != null) return inherited.palette;
    return CupertinoTheme.brightnessOf(this) == Brightness.dark ? PsPalette.dark : PsPalette.light;
  }
}

/// Builds the [CupertinoThemeData] shared by the whole app.
CupertinoThemeData buildCupertinoTheme({Brightness? brightness}) {
  final dark = brightness == Brightness.dark;
  final label = dark ? PsPalette.dark.label : PsPalette.light.label;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: PsPalette.light.accent,
    scaffoldBackgroundColor: const Color(0x00000000),
    barBackgroundColor: const Color(0x00000000),
    textTheme: CupertinoTextThemeData(
      textStyle: PsText.body(label),
      actionTextStyle: PsText.body(PsPalette.light.accent),
      navTitleTextStyle: PsText.headline(label),
      navLargeTitleTextStyle: PsText.largeTitle(label),
      tabLabelTextStyle: PsText.caption(label),
      pickerTextStyle: PsText.body(label),
      dateTimePickerTextStyle: PsText.body(label),
    ),
  );
}
