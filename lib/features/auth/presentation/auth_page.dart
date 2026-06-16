import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  String _activeMethod = 'social';
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _completeAuth(String provider) async {
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    try {
      await ref
          .read(appDraftProvider.notifier)
          .signInWithMockProvider(provider);
    } catch (error) {
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorText = 'Enter both your email and password.';
      });
      return;
    }
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    try {
      await ref.read(appDraftProvider.notifier).signInWithEmailPassword(
            email: email,
            password: password,
          );
    } catch (error) {
      setState(() {
        _errorText = _formatAuthError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatAuthError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length).trim();
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(appConfigProvider);
    final useLiveBackend = config.useLiveBackend;
    final useSupabaseAuth = config.useSupabaseDirectAuth;

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
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          children: [
            const Center(
              child: Hero(
                tag: 'jim-companion',
                child: JimCompanionAvatar(
                  stage: JimCompanionStage.softBase,
                  size: 122,
                  showLabel: true,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Meet Jim',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
            Text(
              useLiveBackend
                  ? useSupabaseAuth
                      ? 'Email and password now sign in directly with Supabase. The returned Supabase session token is then used for protected backend requests.'
                      : 'Email and password now route through the documented FastAPI auth flow. Social providers stay disabled until they are configured.'
                  : 'A soft, smart training companion that grows stronger as you stay consistent. Sign in to shape your coaching style and start building momentum.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: JimColors.inkSoft,
              ),
            ),
            const SizedBox(height: 28),
            JimSurface(
              radius: 34,
              child: Column(
                children: [
                  _AuthOptionTile(
                    icon: Icons.g_mobiledata_rounded,
                    title: 'Continue with Google',
                    subtitle: useLiveBackend
                        ? 'Not configured yet in Supabase'
                        : 'Continue with your coaching setup',
                    onTap:
                        useLiveBackend ? null : () => _completeAuth('google'),
                  ),
                  const SizedBox(height: 12),
                  _AuthOptionTile(
                    icon: Icons.apple_rounded,
                    title: 'Continue with Apple',
                    subtitle: useLiveBackend
                        ? 'Not configured yet in Supabase'
                        : 'Continue with your JimBro profile',
                    onTap: useLiveBackend ? null : () => _completeAuth('apple'),
                  ),
                  const SizedBox(height: 18),
                  if (_errorText != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF2F0),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFFCCC7)),
                      ),
                      child: SelectableText(
                        _errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: JimColors.terracotta,
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _MethodToggle(
                          label: 'Email',
                          selected: _activeMethod == 'email',
                          onTap: () => setState(() => _activeMethod = 'email'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MethodToggle(
                          label: 'Phone no',
                          selected: _activeMethod == 'phone',
                          onTap: () => setState(() => _activeMethod = 'phone'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: JimMotion.gentle,
                    child: _activeMethod == 'email'
                        ? Column(
                            key: const ValueKey('email-form'),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      useLiveBackend
                                          ? useSupabaseAuth
                                              ? 'Supabase email sign in'
                                              : 'Email sign in'
                                          : 'Email sign in',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'Email address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                              ),
                              if (useLiveBackend) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    useSupabaseAuth
                                        ? 'This uses Supabase email/password auth and forwards the Supabase bearer token to future protected FastAPI requests.'
                                        : 'This uses POST /api/v1/auth/login and sends the returned bearer token to future protected requests.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: JimColors.inkSoft,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: JimPrimaryButton(
                                  label: _isSubmitting
                                      ? 'Signing in...'
                                      : useLiveBackend
                                          ? useSupabaseAuth
                                              ? 'Sign in with Supabase'
                                              : 'Sign in with email'
                                          : 'Continue with email',
                                  onPressed: _isSubmitting
                                      ? () {}
                                      : useLiveBackend
                                          ? _submitEmailAuth
                                          : () => _completeAuth('email'),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('phone-form'),
                            children: [
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: 'Phone number',
                                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: JimPrimaryButton(
                                  label: useLiveBackend
                                      ? 'Phone auth unavailable'
                                      : 'Continue with phone',
                                  onPressed: useLiveBackend
                                      ? () {
                                          setState(() {
                                            _errorText =
                                                'Phone auth is not configured yet in Supabase.';
                                          });
                                        }
                                      : () => _completeAuth('phone'),
                                ),
                              ),
                            ],
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

class _AuthOptionTile extends StatelessWidget {
  const _AuthOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: JimColors.eggshell,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: JimColors.insetLine),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: JimColors.accentSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: JimColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
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

class _MethodToggle extends StatelessWidget {
  const _MethodToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: JimMotion.gentle,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? JimColors.accentSoft : JimColors.plaque,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? JimColors.accentLine : JimColors.insetLine,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color:
                        selected ? JimColors.accentStrong : JimColors.inkSoft,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
