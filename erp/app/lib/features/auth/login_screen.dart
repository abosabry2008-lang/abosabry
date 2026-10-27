import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/form_fields.dart';

/// Sign-in screen. Also lets the user override the backend base URL, which is
/// persisted in [SharedPreferences].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  late final TextEditingController _baseUrl =
      TextEditingController(text: AppConfig.baseUrl);

  bool _obscure = true;
  bool _showServerSettings = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();
    final session = context.read<Session>();
    final ok = await session.login(
      email: _email.text,
      password: _password.text,
      baseUrl: _showServerSettings ? _baseUrl.text : null,
    );
    if (!mounted || ok) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(session.error ?? context.s.unableToSignIn)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final busy = session.busy;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.translate),
                tooltip: s.switchLanguageTooltip,
                onPressed: () => context.read<LocaleController>().toggle(),
              ),
            ),
          ),
          Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.account_balance_outlined,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.appName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.inventorySalesTagline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 28),
                      AppTextField(
                        label: s.email,
                        controller: _email,
                        enabled: !busy,
                        prefixIcon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofocus: true,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return s.emailRequired;
                          if (!text.contains('@')) return s.enterValidEmail;
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) =>
                            (value ?? '').isEmpty ? s.passwordIsRequired : null,
                        decoration: InputDecoration(
                          labelText: s.password,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? s.showPassword : s.hidePassword,
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => setState(
                                    () => _showServerSettings =
                                        !_showServerSettings,
                                  ),
                          icon: Icon(
                            _showServerSettings
                                ? Icons.expand_less
                                : Icons.dns_outlined,
                            size: 18,
                          ),
                          label: Text(s.serverSettings),
                        ),
                      ),
                      if (_showServerSettings) ...<Widget>[
                        const SizedBox(height: 4),
                        AppTextField(
                          label: s.apiBaseUrl,
                          controller: _baseUrl,
                          enabled: !busy,
                          prefixIcon: Icons.link,
                          hint: AppConfig.defaultBaseUrl,
                          helperText: s.apiBaseUrlExample,
                          keyboardType: TextInputType.url,
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return s.baseUrlIsRequired;
                            // A relative path such as `/api/v1` is valid on web:
                            // it resolves against the page origin.
                            if (text.startsWith('/')) return null;
                            final uri = Uri.tryParse(text);
                            if (uri == null || !uri.isAbsolute) {
                              return s.enterValidAbsoluteUrl;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: busy
                                ? null
                                : () {
                                    _baseUrl.text = AppConfig.defaultBaseUrl;
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(s.serverReset)),
                                    );
                                  },
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: Text(s.resetToDefaultServer),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : _submit,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(busy ? s.signingIn : s.signIn),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.signedInAsHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}
