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
    required this.userId,
    required this.contact,
    super.key,
  });

  final String userId;
  final String contact;

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  static const int _length = AppConstants.otpLength;

  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List<FocusNode>.generate(_length, (_) => FocusNode());

  bool _submitting = false;
  bool _resending = false;
  String? _error;
  Timer? _resendTimer;
  int _resendSecondsLeft = AppConstants.otpResendCooldown.inSeconds;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = AppConstants.otpResendCooldown.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_resendSecondsLeft <= 1) {
        _resendTimer?.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  String get _otpCode =>
      _controllers.map((c) => c.text).join();

  void _fillCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (int i = 0; i < _length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    if (digits.length >= _length) {
      FocusScope.of(context).unfocus();
      unawaited(_verify());
    } else {
      final next = digits.length.clamp(0, _length - 1);
      _focusNodes[next].requestFocus();
    }
    setState(() {});
  }

  Future<void> _resendCode() async {
    if (widget.userId.isEmpty) {
      setState(() => _error = 'Missing user reference — please register again.');
      return;
    }
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).resendOtp(userId: widget.userId);
      if (!mounted) return;
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend the code. Try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    if (widget.userId.isEmpty) {
      setState(() => _error = 'Missing verification details — please register again.');
      return;
    }
    if (_otpCode.length < _length) {
      setState(() => _error = 'Please enter all $_length digits');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyOtp(
            userId: widget.userId,
            otpCode: _otpCode,
          );
      if (!mounted) return;
      context.go('/home');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // clear boxes on wrong code so the user can retype
        for (final c in _controllers) {
          c.clear();
        }
      });
      _focusNodes[0].requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 12),
              Text(
                'Verify your account',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  children: <InlineSpan>[
                    const TextSpan(text: 'Enter the 6-digit code sent to '),
                    TextSpan(
                      text: widget.contact.isNotEmpty ? widget.contact : 'your account',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _OtpBoxRow(
                controllers: _controllers,
                focusNodes: _focusNodes,
                onFill: _fillCode,
                onChanged: () => setState(() {}),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMd,
                    vertical: AppConstants.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.error_outline, color: scheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Verify',
                loading: _submitting,
                onPressed: _otpCode.length == _length ? _verify : null,
              ),
              const SizedBox(height: 16),
              _ResendButton(
                secondsLeft: _resendSecondsLeft,
                loading: _resending,
                onResend: _resendCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── OTP box row ────────────────────────────────────────────────────────────────

class _OtpBoxRow extends StatelessWidget {
  const _OtpBoxRow({
    required this.controllers,
    required this.focusNodes,
    required this.onFill,
    required this.onChanged,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(String code) onFill;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(controllers.length, (int i) {
        return _OtpBox(
          controller: controllers[i],
          focusNode: focusNodes[i],
          onChanged: (String v) {
            if (v.length > 1) {
              // Paste — fill from first box regardless of which box received it
              onFill(v);
              return;
            }
            if (v.isNotEmpty && i < controllers.length - 1) {
              focusNodes[i + 1].requestFocus();
            }
            onChanged();
            // Auto-submit on last digit
            final String code = controllers.map((c) => c.text).join();
            if (code.length == controllers.length) {
              FocusScope.of(context).unfocus();
            }
          },
          onBackspace: () {
            if (controllers[i].text.isEmpty && i > 0) {
              controllers[i - 1].clear();
              focusNodes[i - 1].requestFocus();
              onChanged();
            }
          },
        );
      }),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool filled = controller.text.isNotEmpty;

    return SizedBox(
      width: 48,
      height: 58,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: filled
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: filled ? scheme.primary : scheme.outlineVariant,
                width: filled ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 2.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Resend button ──────────────────────────────────────────────────────────────

class _ResendButton extends StatelessWidget {
  const _ResendButton({
    required this.secondsLeft,
    required this.loading,
    required this.onResend,
  });

  final int secondsLeft;
  final bool loading;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool canResend = secondsLeft == 0 && !loading;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          "Didn't receive a code?",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 4),
        if (loading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (secondsLeft > 0)
          Text(
            'Resend in ${secondsLeft}s',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          )
        else
          TextButton(
            onPressed: canResend ? onResend : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Resend'),
          ),
      ],
    );
  }
}
