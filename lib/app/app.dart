import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/app_flow.dart';
import '../core/theme/jim_theme.dart';
import '../features/atlas/presentation/atlas_chat_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';

class JimBroApp extends ConsumerWidget {
  const JimBroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'JimBro',
      debugShowCheckedModeBanner: false,
      theme: JimTheme.lightTheme,
      home: const AppFlow(),
      routes: {
        AtlasChatPage.routeName: (_) => const AtlasChatPage(),
        if (kDebugMode)
          OnboardingPreviewPage.routeName: (_) => const OnboardingPreviewPage(),
      },
    );
  }
}
