import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/jim_chat_models.dart';
import '../application/jim_chat_controller.dart';

class AtlasChatPage extends ConsumerStatefulWidget {
  const AtlasChatPage({super.key});

  static const routeName = '/atlas';

  @override
  ConsumerState<AtlasChatPage> createState() => _AtlasChatPageState();
}

class _AtlasChatPageState extends ConsumerState<AtlasChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      return;
    }
    _textController.clear();
    await ref.read(jimChatControllerProvider.notifier).sendMessage(text);
  }

  Future<void> _leave() async {
    await ref.read(jimChatControllerProvider.notifier).endSession();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(jimChatControllerProvider);
    final draft = ref.watch(appDraftProvider).valueOrNull;
    final context = draft?.session == null || draft?.session?.provider == 'mock'
        ? null
        : ref.watch(agentContextProvider).valueOrNull;
    final metricsPending = draft?.session != null &&
        draft?.session?.provider != 'mock' &&
        context != null &&
        context.atlasMetrics == null;
    ref.listen(jimChatControllerProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.messages.lastOrNull?.text !=
              next.messages.lastOrNull?.text) {
        _scrollToBottom();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_leave());
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: JimColors.shell,
        body: SafeArea(
          child: Column(
            children: [
              _ChatHeader(onBack: _leave),
              _ModeSelector(
                selected: chat.session.mode,
                enabled: !chat.isSending,
                onSelected:
                    ref.read(jimChatControllerProvider.notifier).setMode,
              ),
              if (metricsPending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    JimSpacing.ml,
                    JimSpacing.sm,
                    JimSpacing.ml,
                    0,
                  ),
                  child: JimSurface(
                    child: Text(
                      'Coaching metrics are still syncing. Jim can still help with your profile and plan.',
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    JimSpacing.ml,
                    JimSpacing.md,
                    JimSpacing.ml,
                    JimSpacing.md,
                  ),
                  children: [
                    for (final message in chat.messages) ...[
                      _MessageBubble(message: message),
                      const SizedBox(height: JimSpacing.sm),
                    ],
                    if (chat.clarificationOptions.isNotEmpty)
                      _ClarificationOptions(
                        options: chat.clarificationOptions,
                        enabled: !chat.isSending,
                        onSelected: ref
                            .read(jimChatControllerProvider.notifier)
                            .selectClarification,
                      ),
                    if (chat.error != null) ...[
                      const SizedBox(height: JimSpacing.sm),
                      _ChatError(message: chat.error!),
                    ],
                  ],
                ),
              ),
              _ChatComposer(
                controller: _textController,
                enabled: !chat.isSending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JimSpacing.sm,
        JimSpacing.sm,
        JimSpacing.md,
        JimSpacing.xs,
      ),
      child: JimSurface(
        padding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.xs,
          vertical: JimSpacing.xs,
        ),
        radius: JimRadius.lg,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: JimSpacing.xs),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: JimColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: JimColors.accentStrong,
                size: 20,
              ),
            ),
            const SizedBox(width: JimSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Jim', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    'Your coaching companion',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: JimColors.inkMuted,
                        ),
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

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final JimChatMode selected;
  final bool enabled;
  final ValueChanged<JimChatMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: JimSpacing.ml),
      child: Row(
        children: [
          for (final mode in JimChatMode.values) ...[
            ChoiceChip(
              label: Text(_modeLabel(mode)),
              selected: selected == mode,
              onSelected: enabled ? (_) => onSelected(mode) : null,
            ),
            if (mode != JimChatMode.values.last)
              const SizedBox(width: JimSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final JimChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == JimChatRole.user;
    final text = message.text.isEmpty && message.isStreaming
        ? 'Thinking...'
        : message.text;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        child: JimSurface(
          tone: user ? JimSurfaceTone.accent : JimSurfaceTone.plain,
          padding: const EdgeInsets.symmetric(
            horizontal: JimSpacing.md,
            vertical: JimSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: user ? JimColors.ink : null,
                      height: 1.4,
                    ),
              ),
              if (message.isLocalMock && !user) ...[
                const SizedBox(height: JimSpacing.xs),
                Text(
                  'Local mock response',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: JimColors.inkMuted,
                      ),
                ),
              ],
              if (message.isStreaming) ...[
                const SizedBox(height: JimSpacing.xs),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClarificationOptions extends StatelessWidget {
  const _ClarificationOptions({
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  final List<JimClarificationOption> options;
  final bool enabled;
  final ValueChanged<JimClarificationOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: JimSpacing.xs,
      runSpacing: JimSpacing.xs,
      children: [
        for (final option in options)
          ActionChip(
            label: Text(option.label),
            onPressed: enabled ? () => onSelected(option) : null,
          ),
      ],
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return JimSurface(
      tone: JimSurfaceTone.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: JimColors.terracotta),
          const SizedBox(width: JimSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: JimColors.shell,
        border: Border(top: BorderSide(color: JimColors.insetLine)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          JimSpacing.ml,
          JimSpacing.sm,
          JimSpacing.ml,
          JimSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('jim-chat-input'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  labelText: 'Message Jim',
                  hintText: 'Ask about training or nutrition',
                ),
              ),
            ),
            const SizedBox(width: JimSpacing.sm),
            IconButton.filled(
              key: const ValueKey('jim-chat-send'),
              tooltip: 'Send',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(JimChatMode mode) {
  return switch (mode) {
    JimChatMode.general => 'General',
    JimChatMode.workout => 'Workout',
    JimChatMode.nutrition => 'Nutrition',
    JimChatMode.knowledge => 'Knowledge',
  };
}
