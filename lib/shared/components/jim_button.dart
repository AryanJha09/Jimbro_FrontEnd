import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';

class JimPrimaryButton extends StatelessWidget {
  const JimPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: JimColors.accentStrong,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.lg,
          vertical: 15,
        ),
        textStyle: Theme.of(context).textTheme.labelLarge,
        side: BorderSide.none,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.pill),
        ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class JimSecondaryButton extends StatelessWidget {
  const JimSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: JimColors.accent,
        side: const BorderSide(color: JimColors.accentLine),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.lg,
          vertical: 15,
        ),
        backgroundColor: JimColors.plaque,
        textStyle: Theme.of(context).textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.pill),
        ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class JimTextButton extends StatelessWidget {
  const JimTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: JimColors.accentStrong,
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
