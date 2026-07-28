import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../shared/models/app_models.dart';
import '../../home/presentation/home_shell.dart';
import 'workouts_page.dart';

abstract final class WorkoutRoutes {
  static const root = '/app/workouts';
  static const createTemplate = '/app/workouts/templates/new';
  static const history = '/app/workouts/history';

  static String editTemplate(int templateId) =>
      '/app/workouts/templates/$templateId/edit';

  static String activeSession(String sessionId) =>
      '/app/workouts/session/${Uri.encodeComponent(sessionId)}';

  static String finishSummary(String sessionId) =>
      '${activeSession(sessionId)}/end';

  static String historyDetail(int logId) => '$history/$logId';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final uri = Uri.tryParse(settings.name ?? '');
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments;
    if (uri.path == root) {
      return _route(settings, const _WorkoutShellRoute());
    }
    if (uri.path == createTemplate) {
      return _route(
        settings,
        const _TemplateBuilderRoute(create: true),
      );
    }
    if (uri.path == history) {
      return _route(settings, const WorkoutHistoryPage());
    }
    if (segments.length == 5 &&
        segments[0] == 'app' &&
        segments[1] == 'workouts' &&
        segments[2] == 'templates' &&
        segments[4] == 'edit') {
      final templateId = int.tryParse(segments[3]);
      if (templateId != null) {
        return _route(
          settings,
          _TemplateBuilderRoute(templateId: templateId),
        );
      }
    }
    if (segments.length == 5 &&
        segments[0] == 'app' &&
        segments[1] == 'workouts' &&
        segments[2] == 'session' &&
        segments[4] == 'end') {
      final sessionId = Uri.decodeComponent(segments[3]);
      return _route(
        settings,
        WorkoutFinishSummaryPage(
          sessionId: sessionId,
          mutation: settings.arguments is WorkoutMutationResult
              ? settings.arguments! as WorkoutMutationResult
              : null,
        ),
      );
    }
    if (segments.length == 4 &&
        segments[0] == 'app' &&
        segments[1] == 'workouts' &&
        segments[2] == 'session') {
      return _route(
        settings,
        ActiveWorkoutPage(sessionId: Uri.decodeComponent(segments[3])),
      );
    }
    if (segments.length == 4 &&
        segments[0] == 'app' &&
        segments[1] == 'workouts' &&
        segments[2] == 'history') {
      final logId = int.tryParse(segments[3]);
      if (logId != null) {
        return _route(
          settings,
          WorkoutHistoryDetailPage(logId: logId),
        );
      }
    }
    return null;
  }

  static MaterialPageRoute<dynamic> _route(
    RouteSettings settings,
    Widget page,
  ) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => page,
    );
  }
}

class _WorkoutShellRoute extends ConsumerStatefulWidget {
  const _WorkoutShellRoute();

  @override
  ConsumerState<_WorkoutShellRoute> createState() => _WorkoutShellRouteState();
}

class _WorkoutShellRouteState extends ConsumerState<_WorkoutShellRoute> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(
      () => ref.read(currentTabProvider.notifier).state = 1,
    );
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}

class _TemplateBuilderRoute extends ConsumerStatefulWidget {
  const _TemplateBuilderRoute({
    this.create = false,
    this.templateId,
  });

  final bool create;
  final int? templateId;

  @override
  ConsumerState<_TemplateBuilderRoute> createState() =>
      _TemplateBuilderRouteState();
}

class _TemplateBuilderRouteState extends ConsumerState<_TemplateBuilderRoute> {
  Future<void>? _selection;

  @override
  void initState() {
    super.initState();
    _selection = _selectTemplate();
  }

  Future<void> _selectTemplate() async {
    final draft = await ref.read(appDraftProvider.future);
    final controller = ref.read(appDraftProvider.notifier);
    if (widget.create) {
      if (draft.template.templateId != null) {
        await controller.createTemplateDraft();
      }
      return;
    }
    final templateId = widget.templateId;
    if (templateId == null || draft.template.templateId == templateId) {
      return;
    }
    for (final template in draft.templates) {
      if (template.templateId == templateId) {
        await controller.openWorkoutTemplate(template);
        return;
      }
    }
    throw StateError('Workout template $templateId was not found.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _selection,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Template builder')),
            body: Center(child: Text('${snapshot.error}')),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const TemplateBuilderPage();
      },
    );
  }
}
