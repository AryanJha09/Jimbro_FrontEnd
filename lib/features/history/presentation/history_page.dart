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

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading history...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _HistoryContent(draft: draft),
    );
  }
}

class _HistoryContent extends ConsumerWidget {
  const _HistoryContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consistency = draft.consistency;
    final controller = ref.read(appDraftProvider.notifier);
    final insightAsync = ref.watch(historyInsightProvider);
    final recoveryAsync = ref.watch(recoveryInsightProvider);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [JimColors.shell, JimColors.galleryWhite, JimColors.eggshell],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const SectionHeader(
              eyebrow: 'HISTORY',
              title: 'Consistency drives evolution',
            ),
            const SizedBox(height: 18),
            JimSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Companion progress', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      JimCompanionAvatar(
                        stage: consistency.companionStage,
                        size: 110,
                        showLabel: true,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${consistency.currentStreak} day streak',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Longest run: ${consistency.longestStreak} days\nTotal logs: ${consistency.totalLogs}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: JimColors.inkSoft,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    key: const ValueKey(
                                        'decrement-streak-button'),
                                    onPressed: () =>
                                        controller.adjustConsistency(-1),
                                    child: const Text('-1 day'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    key: const ValueKey(
                                        'increment-streak-button'),
                                    onPressed: () =>
                                        controller.adjustConsistency(1),
                                    child: const Text('+1 day'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(
                      7,
                      (index) => Expanded(
                        child: Container(
                          height: index < consistency.weeklyCheckins ? 32 : 18,
                          margin: EdgeInsets.only(right: index == 6 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: index < consistency.weeklyCheckins
                                ? JimColors.accentStrong
                                : JimColors.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            JimSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bench press trend', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(JimRadius.md),
                      color: JimColors.galleryWhite,
                      border: Border.all(color: JimColors.line),
                    ),
                    child: CustomPaint(
                      painter: _TrendPainter(
                          currentStreak: consistency.currentStreak),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            insightAsync.when(
              loading: () => const JimSurface(
                child: Text('Loading trend insight...'),
              ),
              error: (error, stackTrace) => JimSurface(
                child: Text('Trend insight failed: $error'),
              ),
              data: (insight) => InsightCard(insight: insight),
            ),
            const SizedBox(height: 16),
            recoveryAsync.when(
              loading: () => const JimSurface(
                child: Text('Loading recovery insight...'),
              ),
              error: (error, stackTrace) => JimSurface(
                child: Text('Recovery insight failed: $error'),
              ),
              data: (recovery) => InsightCard(insight: recovery),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.currentStreak,
  });

  final int currentStreak;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = JimColors.line
      ..strokeWidth = 1.2;
    final line = Paint()
      ..color = JimColors.accentStrong
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(16, size.height - 20),
      Offset(size.width - 12, size.height - 20),
      axis,
    );
    canvas.drawLine(
      Offset(16, 20),
      Offset(16, size.height - 20),
      axis,
    );

    final lift = currentStreak.clamp(0, 36) / 36;
    final path = Path()
      ..moveTo(24, size.height - 34)
      ..cubicTo(
        size.width * .25,
        size.height - 74,
        size.width * .46,
        size.height - (90 + lift * 18),
        size.width * .62,
        size.height - (116 + lift * 14),
      )
      ..cubicTo(
        size.width * .76,
        size.height - (124 + lift * 10),
        size.width * .84,
        size.height - (118 + lift * 8),
        size.width - 18,
        size.height - (128 + lift * 10),
      );
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.currentStreak != currentStreak;
  }
}
