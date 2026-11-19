import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44, this.inverted = false});

  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: inverted ? Colors.white : c.primary, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text('EZ', style: TextStyle(color: inverted ? c.sidebar : Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.4, letterSpacing: -0.5)),
    );
  }
}

/// Two-panel layout on wide screens, single column on phones.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = Breakpoints.isWide(context);
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: child),
      ),
    );
    if (!wide) return Scaffold(body: SafeArea(child: form));

    const points = [
      ('Fast POS billing', 'Scan, search and charge in a few taps.'),
      ('Customer dues and ledgers', 'Know who owes what, down to the invoice.'),
      ('Stock and purchases', 'Every unit counted, every supplier balance tracked.'),
      ('Reports you can trust', 'Sales, profit and stock from one set of rules.'),
    ];
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              color: c.sidebar,
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const BrandMark(size: 44, inverted: true),
                    const SizedBox(width: 12),
                    Text('EZ POS', style: context.text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ]),
                  const Spacer(),
                  Text('Run your whole\nshop from one place.',
                      style: context.text.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1)),
                  const SizedBox(height: 36),
                  for (final p in points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(margin: const EdgeInsets.only(top: 7), width: 8, height: 8, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(p.$2, style: TextStyle(color: c.sidebarMuted, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Expanded(flex: 4, child: form),
        ],
      ),
    );
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AuthFrame(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!Breakpoints.isWide(context)) ...[const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 52)), const SizedBox(height: 28)],
              Text('Welcome back', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 6),
              Text('Sign in to manage your shop.', style: context.text.bodyLarge?.copyWith(color: c.textMuted)),
              const SizedBox(height: 28),
              AppTextField(controller: _email, label: 'Email', hint: 'you@shop.com', keyboardType: TextInputType.emailAddress, validator: Validators.email, autofillHints: const [AutofillHints.username], textInputAction: TextInputAction.next),
              const SizedBox(height: 16),
              AppTextField(controller: _password, label: 'Password', obscure: true, validator: Validators.required('Password'), autofillHints: const [AutofillHints.password], onSubmitted: (_) => _submit()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                  ),
                ),
              const SizedBox(height: 24),
              AppButton('Sign in', loading: _loading, expand: true, onPressed: _submit),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('New to EZ POS?', style: TextStyle(color: c.textMuted)),
                  TextButton(onPressed: () => context.go('/signup'), child: const Text('Create an account')),
                ],
              ),
              Text('Team members: use the email and password your owner gave you.', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await ref.read(supabaseProvider).auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            data: {'full_name': _name.text.trim()},
          );
      if (res.session == null && mounted) {
        setState(() => _info = 'Check your inbox. We sent a confirmation link to ${_email.text.trim()}. Open it, then sign in.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AuthFrame(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!Breakpoints.isWide(context)) ...[const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 52)), const SizedBox(height: 28)],
            Text('Create your account', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 6),
            Text('You will set up your shop in the next step.', style: context.text.bodyLarge?.copyWith(color: c.textMuted)),
            const SizedBox(height: 28),
            AppTextField(controller: _name, label: 'Your name', validator: Validators.required('Name'), textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
            const SizedBox(height: 16),
            AppTextField(controller: _email, label: 'Email', keyboardType: TextInputType.emailAddress, validator: Validators.email, textInputAction: TextInputAction.next),
            const SizedBox(height: 16),
            AppTextField(controller: _password, label: 'Password', obscure: true, validator: Validators.password, helper: 'At least 8 characters'),
            const SizedBox(height: 16),
            AppTextField(
              controller: _confirm,
              label: 'Confirm password',
              obscure: true,
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(12)), child: Text(_info!, style: TextStyle(color: c.success, fontWeight: FontWeight.w700))),
              ),
            const SizedBox(height: 24),
            AppButton('Create account', loading: _loading, expand: true, onPressed: _submit),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Already have an account?', style: TextStyle(color: c.textMuted)),
                TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _business = TextEditingController();
  late final _owner = TextEditingController(text: (ref.read(supabaseProvider).auth.currentUser?.userMetadata?['full_name'] as String?) ?? '');
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_business, _owner, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('create_business', params: {
        'p': {'name': _business.text.trim(), 'full_name': _owner.text.trim(), 'phone': _phone.text.trim(), 'address': _address.text.trim()},
      });
      ref.invalidate(appUserProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AuthFrame(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!Breakpoints.isWide(context)) ...[const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 52)), const SizedBox(height: 28)],
            Text('Set up your shop', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 6),
            Text('We will prepare payment methods, units and expense categories for you.', style: context.text.bodyLarge?.copyWith(color: c.textMuted)),
            const SizedBox(height: 28),
            AppTextField(controller: _business, label: 'Shop or business name', validator: Validators.required('Business name'), textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
            const SizedBox(height: 16),
            AppTextField(controller: _owner, label: 'Owner name', validator: Validators.required('Owner name'), textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
            const SizedBox(height: 16),
            AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone, validator: Validators.optionalPhone, textInputAction: TextInputAction.next),
            const SizedBox(height: 16),
            AppTextField(controller: _address, label: 'Address', maxLines: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
              ),
            const SizedBox(height: 24),
            AppButton('Create my shop', loading: _loading, expand: true, onPressed: _submit),
            const SizedBox(height: 8),
            TextButton(onPressed: () => ref.read(supabaseProvider).auth.signOut(), child: const Text('Use a different account')),
          ],
        ),
      ),
    );
  }
}
