import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/settings_providers.dart';
import 'theme/app_theme.dart';

class PhantomEyeApp extends ConsumerWidget {
  const PhantomEyeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final onboardingComplete = ref.watch(onboardingCompleteProvider);

    return MaterialApp(
      title: 'Phantom Eye',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(mode),
      theme: AppTheme.light(mode),
      home: onboardingComplete
          ? const AppShell()
          : OnboardingScreen(onComplete: () {}),
    );
  }
}
