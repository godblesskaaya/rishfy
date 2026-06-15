import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/profile_remote_datasource.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstCtrl = TextEditingController();
  final TextEditingController _lastCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _photoCtrl = TextEditingController();

  bool _saving = false;
  String? _error;
  bool _seeded = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _photoCtrl.dispose();
    super.dispose();
  }

  void _seed(User user) {
    if (_seeded) return;
    _firstCtrl.text = user.firstName;
    _lastCtrl.text = user.lastName;
    _emailCtrl.text = user.email ?? '';
    _photoCtrl.text = user.profilePictureUrl ?? '';
    _seeded = true;
  }

  Future<void> _save(User original) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String fullName = <String>[_firstCtrl.text.trim(), _lastCtrl.text.trim()]
        .where((String s) => s.isNotEmpty)
        .join(' ');
    final String email = _emailCtrl.text.trim();
    final String photoUrl = _photoCtrl.text.trim();

    final bool nameChanged = fullName != original.fullName;
    final bool emailChanged = email != (original.email ?? '');
    final bool photoChanged = photoUrl != (original.profilePictureUrl ?? '');
    if (!nameChanged && !emailChanged && !photoChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to save.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      User updated =
          await ref.read(profileRemoteDataSourceProvider).updateProfile(
                fullName: nameChanged ? fullName : null,
                email: emailChanged ? email : null,
              );
      if (photoChanged && photoUrl.isNotEmpty) {
        updated = await ref
            .read(profileRemoteDataSourceProvider)
            .confirmProfilePictureUrl(photoUrl);
      }
      ref.read(authControllerProvider.notifier).updateUser(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      context.pop();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _seed(user);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _firstCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        validator: (String? v) =>
                            v == null || v.trim().isEmpty
                                ? 'First name is required'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        validator: (String? v) =>
                            v == null || v.trim().isEmpty
                                ? 'Last name is required'
                                : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                  validator: (String? v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final bool ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(v.trim());
                    return ok ? null : 'Invalid email';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _photoCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Profile photo URL (optional)',
                  ),
                  validator: (String? v) {
                    final String value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    final Uri? uri = Uri.tryParse(value);
                    return uri != null && uri.hasScheme && uri.hasAuthority
                        ? null
                        : 'Enter a valid URL';
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone),
                  title: const Text('Phone number'),
                  subtitle: Text(user.phoneNumber),
                  trailing: const Text(
                    'Cannot be changed',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Save changes',
                  loading: _saving,
                  onPressed: _saving ? null : () => _save(user),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
