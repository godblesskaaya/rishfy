import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

enum _Step { request, confirm }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _requestFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _confirmFormKey = GlobalKey<FormState>();
  final TextEditingController _otpCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  _Step _step = _Step.request;
  String _identifier = '';
  String _phoneCountryCode = '+255';
  String _phoneNumber = '';
  bool _submitting = false;
  bool _obscurePwd = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (!(_requestFormKey.currentState?.validate() ?? false)) return;
    final String id = '$_phoneCountryCode$_phoneNumber';
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(identifier: id);
      if (!mounted) return;
      setState(() {
        _identifier = id;
        _step = _Step.confirm;
        _info = 'If an account matches that number, we sent a 6-digit code.';
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmReset() async {
    if (!(_confirmFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).confirmPasswordReset(
            identifier: _identifier,
            otpCode: _otpCtrl.text.trim(),
            newPassword: _passwordCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Please log in.')),
      );
      context.go('/login');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reset password. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: _step == _Step.request
              ? _buildRequest(context)
              : _buildConfirm(context),
        ),
      ),
    );
  }

  Widget _buildRequest(BuildContext context) {
    return Form(
      key: _requestFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Reset your password',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the phone number on your account. We will send a 6-digit '
            'code to verify it is you.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          IntlPhoneField(
            initialCountryCode: 'TZ',
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '712 345 678',
            ),
            onChanged: (PhoneNumber p) {
              _phoneCountryCode = p.countryCode;
              _phoneNumber = p.number;
            },
            validator: (PhoneNumber? phone) {
              final String number = phone?.number ?? '';
              if (number.length < 9) return 'Enter a valid phone number';
              return null;
            },
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Send code',
            loading: _submitting,
            onPressed: _submitting ? null : _requestReset,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    return Form(
      key: _confirmFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Enter the code & a new password',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _info!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          TextFormField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: AppConstants.otpLength,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Verification code',
              counterText: '',
            ),
            validator: (String? v) {
              if (v == null || v.length != AppConstants.otpLength) {
                return 'Enter the 6-digit code';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePwd,
            decoration: InputDecoration(
              labelText: 'New password',
              helperText: 'Use at least 8 characters',
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePwd = !_obscurePwd),
                icon: Icon(
                  _obscurePwd ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            validator: (String? v) {
              if (v == null || v.length < 8) return 'Password is too short';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscurePwd,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
            validator: (String? v) {
              if (v != _passwordCtrl.text) return 'Passwords do not match';
              return null;
            },
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Reset password',
            loading: _submitting,
            onPressed: _submitting ? null : _confirmReset,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() => _step = _Step.request),
            child: const Text('Use a different number'),
          ),
        ],
      ),
    );
  }
}
