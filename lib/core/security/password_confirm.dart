import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../errors.dart';
import '../theme/app_colors.dart';
import '../widgets/buttons.dart';
import '../widgets/inputs.dart';

/// Asks the signed-in user for their own password before a sensitive action (void, stock adjustment, reopening a
/// day, changing permissions, deleting a document). Returns true when the action may continue.
///
/// The check calls the database function verify_password, which compares against the stored hash and locks after
/// five wrong tries in ten minutes. It returns true without asking when the owner turned the setting off.
Future<bool> confirmSensitive(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Confirm with your password',
  String message = 'This action changes important records. Enter your password to continue.',
}) async {
  final user = ref.read(currentUserProvider);
  if (!user.business.requirePasswordConfirm) return true;
  final client = ref.read(supabaseProvider);
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      title: title,
      message: message,
      verify: (pw) async => (await client.rpc('verify_password', params: {'p_password': pw})) == true,
    ),
  );
  return ok ?? false;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.message, required this.verify});

  final String title;
  final String message;
  final Future<bool> Function(String password) verify;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _controller.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.verify(pw);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _error = 'Incorrect password.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _controller,
              label: 'Password',
              obscure: !_show,
              autofocus: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        AppButton('Confirm', onPressed: _submit, loading: _busy, dense: true),
      ],
    );
  }
}
