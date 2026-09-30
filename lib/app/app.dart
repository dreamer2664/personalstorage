import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/glass.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/design/widgets.dart';
import '../services/launch_actions.dart';
import '../services/settings.dart';
import 'providers.dart';
import 'shell.dart';

/// Application root: theme, routes (including the `/capture` and `/voice` deep links used by
/// lock-screen widgets and Siri) and the bootstrap splash.
class PersonalStorageApp extends ConsumerWidget {
  const PersonalStorageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final brightness = switch (mode) {
      ThemeModeSetting.system => null,
      ThemeModeSetting.light => Brightness.light,
      ThemeModeSetting.dark => Brightness.dark,
    };
    return CupertinoApp(
      title: 'Personal Storage',
      debugShowCheckedModeBanner: false,
      theme: buildCupertinoTheme(brightness: brightness),
      builder: (context, child) => PsThemeScope(child: child ?? const SizedBox.shrink()),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/capture':
          case '/voice':
            // Deep links: `personalstorage:///capture` and `personalstorage:///voice`.
            // Fire the launch request and immediately step aside - the shell handles it.
            return PageRouteBuilder<void>(
              settings: settings,
              opaque: false,
              transitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => _FireAndPop(type: settings.name == '/voice' ? LaunchActionType.voice : LaunchActionType.capture),
            );
          default:
            return CupertinoPageRoute<void>(settings: settings, builder: (_) => const _Bootstrap());
        }
      },
    );
  }
}

class _FireAndPop extends ConsumerStatefulWidget {
  const _FireAndPop({required this.type});

  final LaunchActionType type;

  @override
  ConsumerState<_FireAndPop> createState() => _FireAndPopState();
}

class _FireAndPopState extends ConsumerState<_FireAndPop> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(launchRequestProvider.notifier).fire(widget.type);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    return services.when(
      data: (_) => const AppShell(),
      loading: () => const _Splash(),
      error: (e, st) => _StartupError(error: e, onRetry: () => ref.invalidate(appServicesProvider)),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return PsScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassPanel(radius: 28, padding: const EdgeInsets.all(22), child: Icon(CupertinoIcons.sparkles, size: 34, color: ps.accent)),
            const SizedBox(height: 18),
            Text('Personal Storage', style: PsText.title(ps.label)),
            const SizedBox(height: 14),
            const CupertinoActivityIndicator(),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return PsScaffold(
      child: PsEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        title: 'Couldn\'t start',
        message: '$error',
        action: PsButton(label: 'Try again', onPressed: onRetry, color: ps.accent),
      ),
    );
  }
}
