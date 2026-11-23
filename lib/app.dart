import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/data/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/feedback.dart';

class EzPosApp extends ConsumerWidget {
  const EzPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppConfig.appName,
        theme: AppTheme.light(),
        home: const _SetupRequired(),
      );
    }
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: router,
    );
  }
}

class _SetupRequired extends StatelessWidget {
  const _SetupRequired();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect EZ POS to Supabase', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text('Start the app with your project URL and anon key:'),
                const SizedBox(height: 12),
                const SelectableText(
                  'flutter run \\\n  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \\\n  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY',
                  style: TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                const Text('See README.md for the full setup, including the database migrations.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
