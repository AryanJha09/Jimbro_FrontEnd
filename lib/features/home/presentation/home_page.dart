import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/insight_card.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/models/app_models.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);

    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading home...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _HomePageContent(draft: draft),
    );
  }
}

class _HomePageContent extends ConsumerWidget {
  const _HomePageContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(atlasHomeInsightsProvider);
    final profile = draft.profile;
    final summary = draft.nutritionSummary;
    final consistency = draft.consistency;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JimColors.shell,
            JimColors.galleryWhite,
            JimColors.eggshell,
          ],
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _HeroPanel(
                      profile: profile,
                      consistency: consistency,
                      onPromptTap: () => _showAtlasPromptExperience(context),
                      onWorkoutTap: () {
                        ref.read(currentTabProvider.notifier).state = 1;
                      },
                    ),
                    const SizedBox(height: 28),
                    const SectionHeader(
                      eyebrow: 'DAILY STATE',
                      title: 'Today at a glance',
                    ),
                    const SizedBox(height: 18),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: .72,
                      children: [
                        _ProgressRingCard(
                          key: const ValueKey('remaining-calories-card'),
                          unit: 'kcal',
                          value: summary.remainingCalories.toStringAsFixed(0),
                          progress:
                              summary.consumedCalories / summary.targetCalories,
                          accentColor: JimColors.accentStrong,
                          subtitle: 'Calories remaining',
                          onTap: () =>
                              ref.read(currentTabProvider.notifier).state = 2,
                        ),
                        _ProgressRingCard(
                          key: const ValueKey('hydration-card'),
                          unit: 'L',
                          value: (summary.hydrationTargetLiters -
                                  summary.hydrationConsumedLiters)
                              .toStringAsFixed(1),
                          progress: summary.hydrationConsumedLiters /
                              summary.hydrationTargetLiters,
                          accentColor: const Color(0xFF83A7E8),
                          subtitle: 'Hydration left',
                          onTap: () =>
                              ref.read(currentTabProvider.notifier).state = 2,
                        ),
                        _MacroOverviewCard(
                          key: const ValueKey('macro-overview-card'),
                          summary: summary,
                          onTap: () =>
                              ref.read(currentTabProvider.notifier).state = 2,
                        ),
                        _StreakCard(
                          key: const ValueKey('tracking-streak-card'),
                          consistency: consistency,
                          onTap: () =>
                              ref.read(currentTabProvider.notifier).state = 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const SectionHeader(
                      eyebrow: 'COACHING LAYER',
                      title: 'What the app sees right now',
                    ),
                    const SizedBox(height: 18),
                    insightsAsync.when(
                      loading: () => const JimSurface(
                        child: Text('Loading coaching insights...'),
                      ),
                      error: (error, stackTrace) => JimSurface(
                        child: Text('Insight loading failed: $error'),
                      ),
                      data: (insights) => Column(
                        children: [
                          for (final insight in insights) ...[
                            InsightCard(insight: insight),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SectionHeader(
                      eyebrow: 'QUICK MOVES',
                      title: 'Jump into the editable prototype',
                    ),
                    const SizedBox(height: 18),
                    JimSurface(
                      child: Column(
                        children: [
                          _FlowTile(
                            icon: Icons.fitness_center_rounded,
                            title: 'Tune your workout draft',
                            subtitle:
                                'Edit exercises, target sets, loads, and notes in-session.',
                            onTap: () =>
                                ref.read(currentTabProvider.notifier).state = 1,
                          ),
                          const SizedBox(height: 12),
                          _FlowTile(
                            icon: Icons.ramen_dining_outlined,
                            title: 'Log food locally',
                            subtitle:
                                'Adjust meal type, grams, and macros without backend saves yet.',
                            onTap: () =>
                                ref.read(currentTabProvider.notifier).state = 2,
                          ),
                          const SizedBox(height: 12),
                          _FlowTile(
                            icon: Icons.person_outline_rounded,
                            title: 'Shape your profile',
                            subtitle:
                                'Change goals, coaching depth, and body metrics to see the UI respond.',
                            onTap: () =>
                                ref.read(currentTabProvider.notifier).state = 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.profile,
    required this.consistency,
    required this.onPromptTap,
    required this.onWorkoutTap,
  });

  final UserProfile profile;
  final ConsistencyState consistency;
  final VoidCallback onPromptTap;
  final VoidCallback onWorkoutTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = consistency.companionStage;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
      decoration: BoxDecoration(
        color: JimColors.plaque,
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: JimColors.insetLine),
        boxShadow: JimElevation.card,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPromptTap,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: JimColors.shell,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JimColors.insetLine),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: JimColors.inkMuted,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ask Jim about training, nutrition, or recovery',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: JimColors.inkMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onPromptTap,
                      icon: const Icon(
                        Icons.mic_none_rounded,
                        color: JimColors.accentStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFFCF8),
                    Color(0xFFF5F1EA),
                    Color(0xFFF1F4FF),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hey ${profile.name}',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Jim is currently in ${stage.name} mode. Keep your streak alive and more armor unlocks.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: JimColors.inkSoft,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _HeroBadge(label: profile.goal),
                            _HeroBadge(label: profile.coachingPreference),
                            _HeroBadge(
                              label: '${consistency.currentStreak} day streak',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  JimCompanionAvatar(
                    stage: stage,
                    size: 136,
                    showLabel: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onWorkoutTap,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: JimColors.accentStrong,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: JimElevation.card,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      'Open today\'s workout draft',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JimColors.plaque,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JimColors.insetLine),
      ),
      child: Text(label),
    );
  }
}

class _ProgressRingCard extends StatelessWidget {
  const _ProgressRingCard({
    super.key,
    required this.unit,
    required this.value,
    required this.progress,
    required this.accentColor,
    required this.subtitle,
    required this.onTap,
  });

  final String unit;
  final String value;
  final double progress;
  final Color accentColor;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: JimSurface(
          padding: const EdgeInsets.all(JimSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  unit,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: JimColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CustomPaint(
                            painter: _RingPainter(
                              progress: progress,
                              accentColor: accentColor,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroOverviewCard extends StatelessWidget {
  const _MacroOverviewCard({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final DailyNutritionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: JimSurface(
          padding: const EdgeInsets.all(JimSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  'g',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: JimColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _MacroBar(
                label: 'Protein',
                amount:
                    '${summary.proteinConsumed.toStringAsFixed(0)} / ${summary.proteinTarget.toStringAsFixed(0)}',
                progress: summary.proteinConsumed / summary.proteinTarget,
                color: JimColors.accentStrong,
              ),
              const SizedBox(height: 10),
              _MacroBar(
                label: 'Carbs',
                amount:
                    '${summary.carbsConsumed.toStringAsFixed(0)} / ${summary.carbsTarget.toStringAsFixed(0)}',
                progress: summary.carbsConsumed / summary.carbsTarget,
                color: const Color(0xFF89A8E1),
              ),
              const SizedBox(height: 10),
              _MacroBar(
                label: 'Fat',
                amount:
                    '${summary.fatConsumed.toStringAsFixed(0)} / ${summary.fatTarget.toStringAsFixed(0)}',
                progress: summary.fatConsumed / summary.fatTarget,
                color: const Color(0xFFAAB6D8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.amount,
    required this.progress,
    required this.color,
  });

  final String label;
  final String amount;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          amount,
          style: theme.textTheme.labelMedium?.copyWith(
            color: JimColors.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: progress.clamp(0, 1),
            backgroundColor: JimColors.accentSoft,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    super.key,
    required this.consistency,
    required this.onTap,
  });

  final ConsistencyState consistency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: JimSurface(
          padding: const EdgeInsets.all(JimSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  'days',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: JimColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${consistency.currentStreak} days',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              JimCompanionAvatar(
                stage: consistency.companionStage,
                size: 82,
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(
                  7,
                  (index) => Expanded(
                    child: Container(
                      height: index < consistency.weeklyCheckins ? 30 : 18,
                      margin: EdgeInsets.only(right: index == 6 ? 0 : 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: index < consistency.weeklyCheckins
                            ? JimColors.accentStrong
                            : JimColors.accentSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.accentColor,
  });

  final double progress;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 12.0;
    final rect = Offset.zero & size;

    final background = Paint()
      ..color = JimColors.accentSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final foreground = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -1.5708,
      6.28318,
      false,
      background,
    );
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -1.5708,
      6.28318 * progress.clamp(0, 1),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor;
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: Container(
          padding: const EdgeInsets.all(JimSpacing.md),
          decoration: BoxDecoration(
            color: JimColors.eggshell,
            borderRadius: BorderRadius.circular(JimRadius.md),
            border: Border.all(color: JimColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: JimColors.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: JimColors.accentStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showAtlasPromptExperience(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Ask Jim',
    barrierColor: Colors.black.withValues(alpha: .12),
    transitionDuration: JimMotion.gentle,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _AtlasPromptOverlay();
    },
  );
}

class _AtlasPromptOverlay extends ConsumerStatefulWidget {
  const _AtlasPromptOverlay();

  @override
  ConsumerState<_AtlasPromptOverlay> createState() =>
      _AtlasPromptOverlayState();
}

class _AtlasPromptOverlayState extends ConsumerState<_AtlasPromptOverlay> {
  late final TextEditingController _controller;
  String _prompt = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedPrompt = _prompt.trim();
    final previewAsync = ref.watch(atlasPromptPreviewProvider(trimmedPrompt));

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.white.withValues(alpha: .18)),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  minWidth: 320,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: JimColors.plaque.withValues(alpha: .98),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: JimColors.insetLine),
                      boxShadow: JimElevation.card,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * .78,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: JimColors.accentSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: JimColors.accentStrong,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Talk to Jim',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'This top bar now behaves like an AI prompt with voice entry.',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: JimColors.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            key: const ValueKey('atlas-prompt-field'),
                            controller: _controller,
                            autofocus: true,
                            minLines: 1,
                            maxLines: 4,
                            onChanged: (value) {
                              setState(() {
                                _prompt = value;
                              });
                            },
                            decoration: InputDecoration(
                              hintText:
                                  'Ask about today\'s workout, protein target, recovery, or form cues...',
                              prefixIcon:
                                  const Icon(Icons.chat_bubble_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _controller.clear();
                                    _prompt = '';
                                  });
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _PromptChip(
                                label: 'How hard should today\'s push day be?',
                              ),
                              _PromptChip(
                                label: 'Am I short on protein today?',
                              ),
                              _PromptChip(
                                label: 'Should I train if I slept badly?',
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _ConversationCard(
                                    label: 'Voice prompt',
                                    icon: Icons.mic_none_rounded,
                                    body:
                                        'Voice capture will live here. Tap the mic from Home to dictate a question or a full workout note.',
                                  ),
                                  const SizedBox(height: 12),
                                  previewAsync.when(
                                    loading: () => const _ConversationCard(
                                      label: 'Response preview',
                                      icon: Icons.auto_awesome_rounded,
                                      body: 'Preparing prompt preview...',
                                    ),
                                    error: (error, stackTrace) =>
                                        _ConversationCard(
                                      label: 'Response preview',
                                      icon: Icons.cloud_off_rounded,
                                      body: 'Prompt preview failed: $error',
                                    ),
                                    data: (insight) => _ConversationCard(
                                      label: insight.title,
                                      icon: Icons.auto_awesome_rounded,
                                      body: insight.mainText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JimColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JimColors.accentLine),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: JimColors.accentStrong,
            ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.label,
    required this.icon,
    required this.body,
  });

  final String label;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JimSpacing.md),
      decoration: BoxDecoration(
        color: JimColors.eggshell,
        borderRadius: BorderRadius.circular(JimRadius.md),
        border: Border.all(color: JimColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: JimColors.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: JimColors.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
