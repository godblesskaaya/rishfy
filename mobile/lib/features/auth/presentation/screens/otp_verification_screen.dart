import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({
    required this.phoneNumber,
    required this.otpReference,
    required this.purpose,
    super.key,
    this.firstName,
    this.lastName,
    this.email,
  });

  final String phoneNumber;
  final String otpReference;
  final String purpose;
  final String? firstName;
  final String? lastName;
  final String? email;

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(
          AppConstants.otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List<FocusNode>.generate(AppConstants.otpLength, (_) => FocusNode());

  String _otpRef = '';
  Timer? _resendTimer;
  int _secondsLeft = 0;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _otpRef = widget.otpReference;
    _startResendCooldown();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode f in _focusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _secondsLeft = AppConstants.otpResendCooldown.inSeconds);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  String get _otpCode => _controllers.map((TextEditingController c) => c.text).join();

  Future<void> _resendOtp() async {
    try {
      final String newRef = await ref
          .read(authControllerProvider.notifier)
          .requestOtp(phoneNumber: widget.phoneNumber, purpose: widget.purpose);
      setState(() {
        _otpRef = newRef;
        _error = null;
      });
      _startResendCooldown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code sent')),
      );
    } on AppException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify() async {
    if (_otpCode.length < AppConstants.otpLength) {
      setState(() => _error = 'Please enter the full code');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final AuthController ctrl = ref.read(authControllerProvider.notifier);
      if (widget.purpose == 'registration') {
        await ctrl.register(
          phoneNumber: widget.phoneNumber,
          firstName: widget.firstName ?? '',
          lastName: widget.lastName ?? '',
          otpCode: _otpCode,
          otpReference: _otpRef,
          email: widget.email,
        );
      } else {
        await ctrl.loginWithOtp(
          phoneNumber: widget.phoneNumber,
          otpCode: _otpCode,
          otpReference: _otpRef,
        );
      }

      if (!mounted) return;

      // The router's redirect will pick up the new auth state and send us home.
      final AsyncValue<AuthState> auth = ref.read(authControllerProvider);
      auth.whenOrNull(
        error: (Object error, _) {
          setState(() =>
              _error = error is AppException ? error.message : 'Login failed');
        },
        data: (AuthState s) {
          if (s.isAuthenticated) {
            context.go('/home');
          }
        },
      );
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 20),
              Text(
                'Verify your number',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(
                      text: widget.phoneNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List<Widget>.generate(
                  AppConstants.otpLength,
                  (int i) => SizedBox(
                    width: 48,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: Theme.of(context).textTheme.headlineMedium,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                      ),
                      onChanged: (String value) {
                        if (value.isNotEmpty && i < AppConstants.otpLength - 1) {
                          _focusNodes[i + 1].requestFocus();
                        } else if (value.isEmpty && i > 0) {
                          _focusNodes[i - 1].requestFocus();
                        }
                        if (_otpCode.length == AppConstants.otpLength) {
                          FocusScope.of(context).unfocus();
                          _verify();
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Verify',
                loading: _submitting,
                onPressed: _verify,
              ),
              const SizedBox(height: 16),
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in ${_secondsLeft}s',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      )
                    : TextButton(
                        onPressed: _resendOtp,
                        child: const Text('Resend code'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
