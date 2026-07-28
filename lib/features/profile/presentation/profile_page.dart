import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_page_scaffold.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/models/app_models.dart';
import '../../../shared/models/onboarding_models.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../onboarding/presentation/onboarding_page.dart';

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

class _ProfileContent extends ConsumerStatefulWidget {
  const _ProfileContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  ConsumerState<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<_ProfileContent> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _goalController;
  late final TextEditingController _availableTimeController;
  late UserLevel _experienceLevel;
  late String _sex;
  late String _activityLevel;
  late String _dietaryPreference;
  late String _trainingPreference;
  bool _isSaving = false;
  bool _isRetryingSync = false;
  bool _isDeletingAccount = false;

  UserProfile get _profile => widget.draft.profile;

  static const _sexOptions = <String>[
    'Prefer not to say',
    'Female',
    'Male',
  ];

  static const _activityOptions = <String>[
    'Mostly sitting',
    'Lightly active',
    'Moderately active',
    'Very active',
    'Changes a lot',
  ];

  static final _dietaryOptions = OnboardingDietaryPreference.values
      .map((preference) => preference.label)
      .toList(growable: false);

  static const _trainingOptions = <String>[
    'Gym workouts',
    'Home workouts',
    'A flexible mix',
    'Not sure yet',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _ageController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();
    _goalController = TextEditingController();
    _availableTimeController = TextEditingController();
    _syncFromProfile(_profile);
  }

  @override
  void didUpdateWidget(covariant _ProfileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSaving && oldWidget.draft.profile != widget.draft.profile) {
      _syncFromProfile(widget.draft.profile);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _goalController.dispose();
    _availableTimeController.dispose();
    super.dispose();
  }

  void _syncFromProfile(UserProfile profile) {
    _nameController.text = profile.name;
    _ageController.text = _positiveIntText(profile.age);
    _heightController.text = _positiveDoubleText(profile.heightCm);
    _weightController.text = _positiveDoubleText(profile.weightKg);
    _goalController.text = profile.goal ?? '';
    _availableTimeController.text =
        _positiveIntText(profile.availableTimeMinutes);
    _experienceLevel = profile.userLevel ?? UserLevel.beginner;
    _sex = _optionOrDefault(profile.sex, _sexOptions);
    _activityLevel = _optionOrDefault(profile.activityLevel, _activityOptions);
    _dietaryPreference = OnboardingDietaryPreference.fromWireValue(
          profile.dietaryPreference,
        )?.label ??
        _dietaryOptions.first;
    _trainingPreference =
        _optionOrDefault(profile.trainingPreference, _trainingOptions);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final metrics = draft.metrics;
    final theme = Theme.of(context);
    final currentName = _nameController.text.trim().isEmpty
        ? 'JimBro User'
        : _nameController.text.trim();
    final currentGoal = _goalController.text.trim().isEmpty
        ? 'Goal not set'
        : _goalController.text.trim();

    return JimPageScaffold(
      eyebrow: 'PROFILE',
      title: 'Shape your coaching plan',
      subtitle:
          'Keep this current so workouts and nutrition targets stay honest.',
      scrollKey: const ValueKey('profile-scroll-view'),
      children: [
        JimSurface(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final avatar = JimCompanionAvatar(
                stage: draft.consistency.companionStage,
                size: 88,
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(currentName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: JimSpacing.xxs),
                  Text(
                    '${_levelLabel(_experienceLevel)} · $currentGoal',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: JimColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: JimSpacing.xxs),
                  Text(
                    '${_display(_activityLevel)} · ${_display(_trainingPreference)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: JimColors.inkMuted,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: JimSpacing.sm),
                    Wrap(
                      spacing: JimSpacing.xs,
                      runSpacing: JimSpacing.xs,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('preview-onboarding-button'),
                          onPressed: () {
                            Navigator.of(context).pushNamed(
                              OnboardingPreviewPage.routeName,
                            );
                          },
                          icon: const Icon(
                            Icons.play_circle_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Preview Onboarding'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey(
                            'restart-onboarding-dev-button',
                          ),
                          onPressed: () async {
                            await ref
                                .read(onboardingControllerProvider.notifier)
                                .reset();
                            ref
                                .read(forceShowOnboardingProvider.notifier)
                                .state = true;
                          },
                          icon: const Icon(Icons.replay_rounded, size: 18),
                          label: const Text('Restart Onboarding (Dev)'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(height: JimSpacing.md),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  avatar,
                  const SizedBox(width: JimSpacing.md),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: JimSpacing.md),
        JimSecondaryButton(
          key: const ValueKey('profile-sign-out-button'),
          label: 'Sign out',
          icon: Icons.logout_rounded,
          expand: true,
          onPressed: _signOut,
        ),
        const SizedBox(height: JimSpacing.sm),
        _DeleteAccountButton(
          isLoading: _isDeletingAccount,
          onPressed: _isDeletingAccount ? null : _confirmDeleteAccount,
        ),
        const SizedBox(height: JimSpacing.md),
        if (draft.profileSyncStatus != ProfileSyncStatus.synced ||
            draft.atlasMetricsStatus != AtlasMetricsStatus.available) ...[
          _ProfileSyncNotice(
            profileSyncStatus: draft.profileSyncStatus,
            atlasMetricsStatus: draft.atlasMetricsStatus,
            isRetrying: _isRetryingSync,
            onRetry: _isRetryingSync ? null : _retryProfileSync,
          ),
          const SizedBox(height: JimSpacing.md),
        ],
        _TargetSummary(metrics: metrics),
        const SizedBox(height: JimSpacing.md),
        JimSurface(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit profile', style: theme.textTheme.titleLarge),
                const SizedBox(height: JimSpacing.xxs),
                Text(
                  'Targets refresh after you save.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JimColors.inkSoft,
                  ),
                ),
                const SizedBox(height: JimSpacing.md),
                TextFormField(
                  key: const ValueKey('profile-name-field'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  validator: _requiredText('Add your name.'),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                TextFormField(
                  key: const ValueKey('profile-goal-field'),
                  controller: _goalController,
                  textInputAction: TextInputAction.next,
                  validator: _requiredText('Add a fitness goal.'),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Fitness goal',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                DropdownButtonFormField<UserLevel>(
                  initialValue: _experienceLevel,
                  isExpanded: true,
                  items: UserLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(_levelLabel(level)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _experienceLevel = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Experience level',
                    prefixIcon: Icon(Icons.layers_outlined),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                _NumberPair(
                  first: TextFormField(
                    key: const ValueKey('profile-age-field'),
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) => _intRange(
                      value,
                      min: 13,
                      max: 100,
                      message: 'Use 13-100.',
                    ),
                    decoration: const InputDecoration(labelText: 'Age'),
                  ),
                  second: _OptionField(
                    value: _sex,
                    options: _sexOptions,
                    label: 'Sex',
                    onChanged: (value) => setState(() => _sex = value),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                _NumberPair(
                  first: TextFormField(
                    key: const ValueKey('profile-height-field'),
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _doubleRange(
                      value,
                      min: 90,
                      max: 240,
                      message: 'Use 90-240 cm.',
                    ),
                    decoration: const InputDecoration(labelText: 'Height cm'),
                  ),
                  second: TextFormField(
                    key: const ValueKey('profile-weight-field'),
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _doubleRange(
                      value,
                      min: 25,
                      max: 300,
                      message: 'Use 25-300 kg.',
                    ),
                    decoration: const InputDecoration(labelText: 'Weight kg'),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                _OptionField(
                  value: _activityLevel,
                  options: _activityOptions,
                  label: 'Activity level',
                  icon: Icons.directions_walk_rounded,
                  onChanged: (value) => setState(() => _activityLevel = value),
                ),
                const SizedBox(height: JimSpacing.sm),
                _OptionField(
                  value: _dietaryPreference,
                  options: _dietaryOptions,
                  label: 'Dietary preference',
                  icon: Icons.restaurant_menu_rounded,
                  onChanged: (value) =>
                      setState(() => _dietaryPreference = value),
                ),
                const SizedBox(height: JimSpacing.sm),
                TextFormField(
                  key: const ValueKey('profile-available-time-field'),
                  controller: _availableTimeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => _intRange(
                    value,
                    min: 10,
                    max: 180,
                    message: 'Use 10-180 minutes.',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Available time min',
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                ),
                const SizedBox(height: JimSpacing.sm),
                _OptionField(
                  value: _trainingPreference,
                  options: _trainingOptions,
                  label: 'Training preference',
                  icon: Icons.fitness_center_rounded,
                  onChanged: (value) =>
                      setState(() => _trainingPreference = value),
                ),
                const SizedBox(height: JimSpacing.md),
                JimPrimaryButton(
                  key: const ValueKey('profile-save-button'),
                  label: _isSaving ? 'Saving...' : 'Save profile',
                  icon: Icons.check_rounded,
                  expand: true,
                  onPressed: _isSaving ? () {} : _saveProfile,
                ),
              ],
            ),
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: JimSpacing.md),
          const _DevOnboardingControls(),
        ],
      ],
    );
  }

  Future<void> _saveProfile() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final profile = _profile.copyWith(
        name: _nameController.text.trim(),
        goal: _goalController.text.trim(),
        userLevel: _experienceLevel,
        age: int.parse(_ageController.text.trim()),
        sex: _sex,
        heightCm: double.parse(_heightController.text.trim()),
        weightKg: double.parse(_weightController.text.trim()),
        activityLevel: _activityLevel,
        dietaryPreference:
            OnboardingDietaryPreference.fromLabel(_dietaryPreference)
                    ?.wireValue ??
                '',
        availableTimeMinutes: int.parse(_availableTimeController.text.trim()),
        trainingPreference: _trainingPreference,
      );
      final result = await ref.read(appDraftProvider.notifier).updateProfile(
            profile,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result?.warning ?? 'Profile saved. Targets refreshed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save profile. Your latest edits are still here.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _signOut() async {
    await ref.read(appDraftProvider.notifier).signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    if (_isDeletingAccount) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final colorScheme = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              title: const Text('Delete your account?'),
              content: const Text(
                'This permanently deletes your account and all your data. '
                'This cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!mounted || !confirmed) {
      return;
    }
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    if (_isDeletingAccount) {
      return;
    }
    setState(() => _isDeletingAccount = true);
    try {
      await ref.read(appDraftProvider.notifier).deleteAccount();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            presentAppError(
              error,
              fallbackMessage:
                  'Unable to delete your account. Please try again.',
              method: 'DELETE',
              route: '/account',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  Future<void> _retryProfileSync() async {
    setState(() => _isRetryingSync = true);
    try {
      final result =
          await ref.read(appDraftProvider.notifier).retryProfileSync();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result?.warning ?? 'Coaching profile synced. Targets refreshed.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Coaching sync is still unavailable. Your profile is safe here.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetryingSync = false);
      }
    }
  }

  String? Function(String?) _requiredText(String message) {
    return (value) => value == null || value.trim().isEmpty ? message : null;
  }

  String? _intRange(
    String? value, {
    required int min,
    required int max,
    required String message,
  }) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < min || parsed > max) {
      return message;
    }
    return null;
  }

  String? _doubleRange(
    String? value, {
    required double min,
    required double max,
    required String message,
  }) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < min || parsed > max) {
      return message;
    }
    return null;
  }
}

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: isLoading ? 'Deleting account' : 'Delete Account',
      child: OutlinedButton(
        key: const ValueKey('profile-delete-account-button'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: JimColors.terracotta,
          disabledForegroundColor: JimColors.terracotta.withValues(alpha: .55),
          side: BorderSide(
            color: isLoading
                ? JimColors.terracotta.withValues(alpha: .35)
                : JimColors.terracotta.withValues(alpha: .62),
          ),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(
            horizontal: JimSpacing.lg,
            vertical: 15,
          ),
          backgroundColor: colorScheme.error.withValues(alpha: .06),
          textStyle: Theme.of(context).textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JimRadius.pill),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    JimColors.terracotta.withValues(alpha: .78),
                  ),
                ),
              )
            else
              const Icon(Icons.delete_forever_rounded, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                isLoading ? 'Deleting...' : 'Delete Account',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSyncNotice extends StatelessWidget {
  const _ProfileSyncNotice({
    required this.profileSyncStatus,
    required this.atlasMetricsStatus,
    required this.isRetrying,
    required this.onRetry,
  });

  final ProfileSyncStatus profileSyncStatus;
  final AtlasMetricsStatus atlasMetricsStatus;
  final bool isRetrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metricsPending = atlasMetricsStatus != AtlasMetricsStatus.available;
    return JimSurface(
      tone: JimSurfaceTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coaching sync pending',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: JimSpacing.xxs),
          Text(
            metricsPending
                ? 'Your profile is saved here. Jim is using local estimates until coaching metrics finish syncing.'
                : 'Your profile is saved here and will retry its coaching sync shortly.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: JimColors.inkSoft,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: JimSpacing.sm),
          JimSecondaryButton(
            label: isRetrying ? 'Retrying...' : 'Retry coaching sync',
            icon: Icons.sync_rounded,
            onPressed: onRetry ?? () {},
          ),
        ],
      ),
    );
  }
}

class _TargetSummary extends StatelessWidget {
  const _TargetSummary({
    required this.metrics,
  });

  final UserStaticMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final hasTargets = metrics.targetCalories > 0 &&
        metrics.proteinG > 0 &&
        metrics.hydrationL > 0;

    return JimSurface(
      tone: JimSurfaceTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calculated targets',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: JimSpacing.xxs),
          Text(
            hasTargets
                ? 'Guidance estimates from your profile.'
                : 'Add age, sex, height, weight, goal, and activity to estimate.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: JimColors.inkSoft,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: JimSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                JimMetricCard(
                  label: 'Calorie target',
                  value: hasTargets
                      ? '${metrics.targetCalories.round()} kcal'
                      : 'Not set',
                  icon: Icons.local_fire_department_rounded,
                ),
                JimMetricCard(
                  label: 'Protein target',
                  value:
                      hasTargets ? '${metrics.proteinG.round()} g' : 'Not set',
                  icon: Icons.egg_alt_outlined,
                ),
                JimMetricCard(
                  label: 'Hydration target',
                  value: hasTargets
                      ? '${metrics.hydrationL.toStringAsFixed(1)} L'
                      : 'Not set',
                  icon: Icons.water_drop_outlined,
                ),
                JimMetricCard(
                  label: 'TDEE',
                  value: metrics.tdee > 0
                      ? '${metrics.tdee.round()} kcal'
                      : 'Not set',
                  icon: Icons.speed_rounded,
                ),
              ];
              final useSingleColumn = constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.3;
              if (useSingleColumn) {
                return Column(
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      cards[index],
                      if (index != cards.length - 1)
                        const SizedBox(height: JimSpacing.sm),
                    ],
                  ],
                );
              }
              return GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: JimSpacing.sm,
                  mainAxisSpacing: JimSpacing.sm,
                  mainAxisExtent: 140,
                ),
                children: cards,
              );
            },
          ),
          if (metrics.cutIntensity.isNotEmpty) ...[
            const SizedBox(height: JimSpacing.sm),
            Text(
              metrics.cutIntensity,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.inkMuted,
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionField extends StatelessWidget {
  const _OptionField({
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
    this.icon,
  });

  final String value;
  final List<String> options;
  final String label;
  final ValueChanged<String> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dropdownOptions = value.trim().isNotEmpty && !options.contains(value)
        ? [value, ...options]
        : options;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: dropdownOptions
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
    );
  }
}

class _NumberPair extends StatelessWidget {
  const _NumberPair({
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              first,
              const SizedBox(height: JimSpacing.sm),
              second,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: JimSpacing.sm),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _DevOnboardingControls extends ConsumerWidget {
  const _DevOnboardingControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return JimSurface(
      backgroundColor: JimColors.accentSoft.withValues(alpha: .45),
      borderColor: JimColors.accentLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Onboarding dev tools', style: theme.textTheme.titleLarge),
          const SizedBox(height: JimSpacing.xs),
          Text(
            'Debug-only controls for replaying onboarding without signing out or deleting the current session.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: JimColors.inkSoft,
              height: 1.35,
            ),
          ),
          const SizedBox(height: JimSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('reset-onboarding-flag-dev-button'),
              onPressed: () async {
                await ref.read(onboardingControllerProvider.notifier).reset();
                ref.read(forceShowOnboardingProvider.notifier).state = true;
              },
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Reset Onboarding Flag (Dev)'),
            ),
          ),
        ],
      ),
    );
  }
}

String _positiveIntText(int? value) =>
    value != null && value > 0 ? value.toString() : '';

String _positiveDoubleText(double? value) {
  if (value == null || value <= 0) {
    return '';
  }
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

String _optionOrDefault(String? value, List<String> options) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return options.first;
  }
  return options.firstWhere(
    (option) => option.toLowerCase() == trimmed.toLowerCase(),
    orElse: () => trimmed,
  );
}

String _levelLabel(UserLevel level) {
  return switch (level) {
    UserLevel.beginner => 'Beginner',
    UserLevel.intermediate => 'Intermediate',
    UserLevel.advanced => 'Advanced',
  };
}

String _display(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Not set' : trimmed;
}
