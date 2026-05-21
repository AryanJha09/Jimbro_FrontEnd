import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/models/app_models.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading profile...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _ProfileContent(draft: draft),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appDraftProvider.notifier);
    final profile = draft.profile;
    final metrics = draft.metrics;
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
              eyebrow: 'PROFILE',
              title: 'Shape your local prototype',
            ),
            const SizedBox(height: 18),
            JimSurface(
              child: Row(
                children: [
                  JimCompanionAvatar(
                    stage: draft.consistency.companionStage,
                    size: 92,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name,
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${profile.userLevel.name} lifter · ${profile.goal}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: JimColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Jim stage: ${draft.consistency.companionStage.name}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: JimColors.inkMuted,
                          ),
                        ),
                      ],
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
                  Text('Identity', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('profile-name-field'),
                    initialValue: profile.name,
                    onChanged: (value) =>
                        controller.updateProfile(profile.copyWith(name: value)),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserLevel>(
                    initialValue: profile.userLevel,
                    items: UserLevel.values
                        .map(
                          (level) => DropdownMenuItem(
                            value: level,
                            child: Text(level.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller
                            .updateProfile(profile.copyWith(userLevel: value));
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'User level',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: profile.goal,
                    onChanged: (value) =>
                        controller.updateProfile(profile.copyWith(goal: value)),
                    decoration: const InputDecoration(
                      labelText: 'Goal',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: profile.coachingPreference,
                    onChanged: (value) => controller.updateProfile(
                        profile.copyWith(coachingPreference: value)),
                    decoration: const InputDecoration(
                      labelText: 'Coaching preference',
                      prefixIcon: Icon(Icons.psychology_alt_outlined),
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
                  Text('Body metrics', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricField(
                          label: 'Age',
                          initialValue: '${profile.age}',
                          onChanged: (value) => controller.updateProfile(
                            profile.copyWith(
                                age: int.tryParse(value) ?? profile.age),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricField(
                          label: 'Height cm',
                          initialValue: '${profile.heightCm}',
                          onChanged: (value) => controller.updateProfile(
                            profile.copyWith(
                              heightCm:
                                  double.tryParse(value) ?? profile.heightCm,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricField(
                          label: 'Weight kg',
                          initialValue: '${profile.weightKg}',
                          onChanged: (value) => controller.updateProfile(
                            profile.copyWith(
                              weightKg:
                                  double.tryParse(value) ?? profile.weightKg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            JimSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Static metrics', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricField(
                          label: 'BMR',
                          initialValue: '${metrics.bmr}',
                          onChanged: (value) => controller.updateMetrics(
                            metrics.copyWith(
                                bmr: double.tryParse(value) ?? metrics.bmr),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricField(
                          label: 'TDEE',
                          initialValue: '${metrics.tdee}',
                          onChanged: (value) => controller.updateMetrics(
                            metrics.copyWith(
                              tdee: double.tryParse(value) ?? metrics.tdee,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricField(
                          label: 'Protein g',
                          initialValue: '${metrics.proteinG}',
                          onChanged: (value) => controller.updateMetrics(
                            metrics.copyWith(
                              proteinG:
                                  double.tryParse(value) ?? metrics.proteinG,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricField(
                          label: 'Carbs g',
                          initialValue: '${metrics.carbsG}',
                          onChanged: (value) => controller.updateMetrics(
                            metrics.copyWith(
                              carbsG: double.tryParse(value) ?? metrics.carbsG,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricField(
                          label: 'Fat g',
                          initialValue: '${metrics.fatG}',
                          onChanged: (value) => controller.updateMetrics(
                            metrics.copyWith(
                              fatG: double.tryParse(value) ?? metrics.fatG,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}
