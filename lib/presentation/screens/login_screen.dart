// lib/presentation/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_identity.dart';
import '../../core/app_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/university.dart';
import '../providers/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text;

      await ref.read(remoteDatasourceProvider).verifyCredentials(
            username: username,
            password: password,
          );

      await auth.saveCredentials(
        username,
        password,
      );

      if (!mounted) return;
      ref.read(pendingGroupSetupProvider.notifier).state = true;
      ref.invalidate(credentialsProvider);
      ref.invalidate(isLoggedInProvider);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final failure = AppFailure.from(e);
        _error = '${failure.title}\n${failure.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final university =
        ref.watch(universityProvider).valueOrNull ?? University.uek;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.school_outlined),
                          title: Text(university.shortName),
                          subtitle: Text(university.name),
                          trailing: IconButton(
                              tooltip: 'Zmień uczelnię',
                              icon: const Icon(Icons.swap_horiz_rounded),
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.of(context)
                                      .pushReplacementNamed('/university')),
                        ),
                        SizedBox(height: 24),
                        // Logo / Header
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(appIconAsset,
                                width: 80, height: 80),
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          appName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Zaloguj się używając danych do USOS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.onSurfaceMuted,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 48),
                        TextFormField(
                          controller: _usernameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Login USOS',
                            prefixIcon: Icon(Icons.person_outline_rounded,
                                color: AppColors.onSurfaceMuted),
                          ),
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Podaj login'
                              : null,
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: InputDecoration(
                            labelText: 'Hasło',
                            prefixIcon: Icon(Icons.lock_outline_rounded,
                                color: AppColors.onSurfaceMuted),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.onSurfaceMuted,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Podaj hasło' : null,
                        ),
                        SizedBox(height: 24),
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: AppColors.error, fontSize: 13),
                            ),
                          ),
                        if (_error != null) SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : Text('Zaloguj się'),
                        ),
                        SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Dane logowania są przechowywane w zabezpieczonej pamięci urządzenia i używane wyłącznie do logowania w serwisach UEK: planie zajęć, USOS i portalu obecności.',
                            style: TextStyle(
                              color: AppColors.onSurfaceMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))),
        ),
      ),
    );
  }
}
