import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/auth/auth_gateway.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../core/widgets/theme_toggle.dart';
import '../../../l10n/app_localizations.dart';
import '../../agent/presentation/kiu_bubble.dart';
import '../../agent/presentation/kiu_illustration.dart';

/// Sign-up / sign-in in as few taps as possible: Google, Facebook (when
/// configured) or email + password. Then straight to Kiu.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.services});
  final AppServices services;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true;
  // Owned by the page (not the dialog) so its closing animation never sees disposed controllers.
  final _gEmail = TextEditingController(text: 'ana@kiupop.test');
  final _gName = TextEditingController(text: 'Ana Prueba');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _gEmail.dispose();
    _gName.dispose();
    super.dispose();
  }

  AuthGateway get _auth => widget.services.auth;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      context.go('/kiu');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = _message(AppLocalizations.of(context), e.failure),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _message(AppLocalizations l10n, AuthFailure f) => switch (f) {
    AuthFailure.invalidCredentials => l10n.authInvalidCredentials,
    AuthFailure.emailInUse => l10n.authEmailInUse,
    AuthFailure.weakPassword => l10n.authWeakPassword,
    AuthFailure.invalidEmail => l10n.authInvalidEmail,
    AuthFailure.popupClosed => null,
    AuthFailure.providerDisabled => l10n.authProviderDisabled,
    AuthFailure.network => l10n.authNetwork,
    AuthFailure.unknown => l10n.authUnknown,
  };

  /// Real Google popup in production; in local mode the emulator needs a test
  /// identity, so we ask for one (clearly labelled, no real Google account).
  Future<void> _google() async {
    if (_auth.mode != 'emulator') return _run(_auth.signInWithGoogle);
    final l10n = AppLocalizations.of(context);
    final email = _gEmail, name = _gName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(l10n.googleTestTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.googleTestBody),
            const SizedBox(height: 12),
            TextField(
              key: const Key('google-test-name'),
              controller: name,
              decoration: InputDecoration(labelText: l10n.googleTestName),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('google-test-email'),
              controller: email,
              decoration: InputDecoration(labelText: l10n.loginEmail),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('google-test-continue'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.loginSignIn),
          ),
        ],
      ),
    );
    final e = email.text, n = name.text;
    if (ok == true) {
      await _run(() => _auth.signInWithGoogle(testEmail: e, testName: n));
    }
  }

  void _submitEmail() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final pw = _password.text;
    _run(
      () => _register
          ? _auth.registerWithEmail(email, pw)
          : _auth.signInWithEmail(email, pw),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final introduction = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.kiuLoginTitle,
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: KPopSpace.xs),
        Text(
          l10n.loginSubtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.loginHowItWorks, style: theme.textTheme.titleMedium),
        const SizedBox(height: KPopSpace.sm),
        for (final (tint, icon, text) in [
          (KPopTint.peach, Icons.login_rounded, l10n.welcomeStep1),
          (KPopTint.mint, Icons.chat_bubble_outline_rounded, l10n.welcomeStep2),
          (KPopTint.bubblegum, Icons.storefront_outlined, l10n.welcomeStep3),
        ]) ...[
          KPopClayTile(tint: tint, icon: icon, label: text),
          const SizedBox(height: KPopSpace.xs),
        ],
      ],
    );
    final links = Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          onPressed: () => context.go('/s/tienda-demo'),
          child: Text(l10n.loginJustLooking, textAlign: TextAlign.center),
        ),
        TextButton(
          onPressed: () => context.go('/clave'),
          child: Text(l10n.loginLegacyKey, textAlign: TextAlign.center),
        ),
      ],
    );
    return KPopScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.back,
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const KiuPopLogo(size: 36),
        actions: [ThemeToggle(controller: widget.services.theme)],
      ),
      body: SingleChildScrollView(
        child: PageBody(
          maxWidth: 1080,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final form = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide) ...[
                    const Center(
                      child: KiuBubbleAnimation(size: 112, mood: KiuMood.idle),
                    ),
                    const SizedBox(height: KPopSpace.sm),
                    introduction,
                  ],
                  if (_auth.mode == 'emulator') ...[
                    const SizedBox(height: KPopSpace.sm),
                    _Notice(text: l10n.loginEmulatorNotice),
                  ],
                  if (_auth.mode == 'disabled') ...[
                    const SizedBox(height: KPopSpace.sm),
                    _Notice(text: l10n.loginDisabledNotice),
                  ],
                  const SizedBox(height: KPopSpace.md),
                  KPopButton(
                    key: const Key('login-google'),
                    tone: KPopButtonTone.tonal,
                    expand: true,
                    onPressed: _busy || !_auth.googleEnabled ? null : _google,
                    icon: Icons.account_circle_outlined,
                    label: l10n.loginGoogle,
                  ),
                  const SizedBox(height: KPopSpace.xs),
                  Tooltip(
                    message: _auth.facebookEnabled
                        ? ''
                        : l10n.loginFacebookPending,
                    child: OutlinedButton.icon(
                      key: const Key('login-facebook'),
                      onPressed: _busy || !_auth.facebookEnabled
                          ? null
                          : () => _run(_auth.signInWithFacebook),
                      icon: const Icon(Icons.facebook_rounded),
                      label: Text(
                        _auth.facebookEnabled
                            ? l10n.loginFacebook
                            : l10n.loginFacebookSoon,
                      ),
                    ),
                  ),
                  const SizedBox(height: KPopSpace.md),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Flexible(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KPopSpace.sm,
                          ),
                          child: Text(
                            l10n.loginOrEmail,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const Key('login-email'),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l10n.loginEmail,
                            ),
                            validator: (v) =>
                                (v ?? '').contains('@') &&
                                    (v ?? '').trim().length >= 5
                                ? null
                                : l10n.authInvalidEmail,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('login-password'),
                            controller: _password,
                            obscureText: true,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: l10n.loginPassword,
                              helperText: _register
                                  ? l10n.loginPasswordHelp
                                  : null,
                            ),
                            validator: (v) => (v ?? '').length >= 6
                                ? null
                                : l10n.authWeakPassword,
                            onFieldSubmitted: (_) => _submitEmail(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                        key: const Key('login-error'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('login-submit'),
                    onPressed: _busy ? null : _submitEmail,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(
                            _register
                                ? l10n.loginCreateAccount
                                : l10n.loginSignIn,
                          ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _register = !_register),
                    child: Text(
                      _register ? l10n.loginHaveAccount : l10n.loginNoAccount,
                    ),
                  ),
                  const SizedBox(height: KPopSpace.sm),
                  links,
                ],
              );
              return Padding(
                padding: const EdgeInsets.only(
                  top: KPopSpace.md,
                  bottom: KPopSpace.xl,
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const KiuIllustration(
                                  height: 300,
                                  mood: KiuMood.idle,
                                ),
                                const SizedBox(height: KPopSpace.lg),
                                introduction,
                                const SizedBox(height: KPopSpace.lg),
                                steps,
                              ],
                            ),
                          ),
                          const SizedBox(width: KPopSpace.lg),
                          Expanded(child: KPopCard(child: form)),
                        ],
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: form,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) =>
      KPopBanner(text: text, icon: Icons.science_outlined);
}
