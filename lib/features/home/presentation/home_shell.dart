import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../history/presentation/history_page.dart';
import '../../nutrition/presentation/nutrition_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../workouts/presentation/workouts_page.dart';
import 'home_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _pageFactories = <Widget Function()>[
    HomePage.new,
    WorkoutsPage.new,
    NutritionPage.new,
    HistoryPage.new,
    ProfilePage.new,
  ];

  late final List<Widget?> _pages =
      List<Widget?>.filled(_pageFactories.length, null);

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    _pages[currentTab] ??= _pageFactories[currentTab]();

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentTab,
        children: List<Widget>.generate(
          _pages.length,
          (index) => _pages[index] ?? const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: JimColors.plaque.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(JimRadius.lg),
            border: Border.all(color: JimColors.insetLine),
            boxShadow: JimElevation.card,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(JimRadius.lg),
            child: BottomNavigationBar(
              currentIndex: currentTab,
              onTap: (index) =>
                  ref.read(currentTabProvider.notifier).state = index,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined), label: ''),
                BottomNavigationBarItem(
                    icon: Icon(Icons.fitness_center_rounded), label: ''),
                BottomNavigationBarItem(
                    icon: Icon(Icons.ramen_dining_outlined), label: ''),
                BottomNavigationBarItem(
                    icon: Icon(Icons.show_chart_rounded), label: ''),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline_rounded), label: ''),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
