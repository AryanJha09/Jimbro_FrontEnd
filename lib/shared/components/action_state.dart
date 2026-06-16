import 'package:flutter/material.dart';

import 'jim_button.dart';

enum JimActionStatus {
  idle,
  loading,
  success,
  error,
}

class JimGuardedPrimaryButton extends StatefulWidget {
  const JimGuardedPrimaryButton({
    super.key,
    required this.label,
    required this.loadingLabel,
    required this.icon,
    required this.onRun,
    this.expand = false,
    this.onSuccess,
    this.onError,
  });

  final String label;
  final String loadingLabel;
  final IconData icon;
  final Future<void> Function() onRun;
  final bool expand;
  final VoidCallback? onSuccess;
  final ValueChanged<Object>? onError;

  @override
  State<JimGuardedPrimaryButton> createState() =>
      _JimGuardedPrimaryButtonState();
}

class _JimGuardedPrimaryButtonState extends State<JimGuardedPrimaryButton> {
  JimActionStatus _status = JimActionStatus.idle;

  bool get _isLoading => _status == JimActionStatus.loading;

  @override
  Widget build(BuildContext context) {
    return JimPrimaryButton(
      label: _isLoading ? widget.loadingLabel : widget.label,
      icon: _isLoading ? Icons.sync_rounded : widget.icon,
      expand: widget.expand,
      onPressed: _isLoading ? () {} : _run,
    );
  }

  Future<void> _run() async {
    if (_isLoading) {
      return;
    }
    setState(() => _status = JimActionStatus.loading);
    try {
      await widget.onRun();
      if (!mounted) {
        return;
      }
      setState(() => _status = JimActionStatus.success);
      widget.onSuccess?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = JimActionStatus.error);
      widget.onError?.call(error);
    }
  }
}

class JimGuardedIconButton extends StatefulWidget {
  const JimGuardedIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onRun,
    this.onSuccess,
    this.onError,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onRun;
  final VoidCallback? onSuccess;
  final ValueChanged<Object>? onError;

  @override
  State<JimGuardedIconButton> createState() => _JimGuardedIconButtonState();
}

class _JimGuardedIconButtonState extends State<JimGuardedIconButton> {
  JimActionStatus _status = JimActionStatus.idle;

  bool get _isLoading => _status == JimActionStatus.loading;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: widget.tooltip,
      onPressed: _isLoading ? null : _run,
      icon: Icon(_isLoading ? Icons.sync_rounded : widget.icon),
    );
  }

  Future<void> _run() async {
    if (_isLoading) {
      return;
    }
    setState(() => _status = JimActionStatus.loading);
    try {
      await widget.onRun();
      if (!mounted) {
        return;
      }
      setState(() => _status = JimActionStatus.success);
      widget.onSuccess?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = JimActionStatus.error);
      widget.onError?.call(error);
    }
  }
}
