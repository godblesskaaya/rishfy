import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/payment_method.dart';
import '../providers/payment_methods_provider.dart';

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PaymentMethod> methods = ref.watch(paymentMethodsProvider);

    Future<void> showEditor({PaymentMethod? existing}) async {
      final PaymentMethod? result =
          await showModalBottomSheet<PaymentMethod>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _MethodEditorSheet(existing: existing),
      );
      if (result == null) return;
      if (existing == null) {
	                    await ref.read(paymentMethodsProvider.notifier).add(
	              label: result.label,
	              provider: result.provider,
	              phone: result.phone,
	              isDefault: result.isDefault,
	            );
      } else {
        await ref.read(paymentMethodsProvider.notifier).update(result);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showEditor,
        icon: const Icon(Icons.add),
        label: const Text('Add method'),
      ),
      body: methods.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.account_balance_wallet, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'No saved methods yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save your mobile money numbers so you can book a ride '
                      'with a single tap.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: methods.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext ctx, int i) {
                final PaymentMethod m = methods[i];
	                return ListTile(
	                  leading: Icon(
	                    m.isDefault ? Icons.check_circle : Icons.payment,
	                  ),
	                  title: Text(m.label.isEmpty ? m.providerDisplayName : m.label),
	                  subtitle: Text(
	                    m.isDefault
	                        ? '${m.providerDisplayName} · ${m.phone} · Default'
	                        : '${m.providerDisplayName} · ${m.phone}',
	                  ),
	                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final bool? ok = await showDialog<bool>(
                        context: ctx,
                        builder: (BuildContext dCtx) => AlertDialog(
                          title: const Text('Delete payment method?'),
                          content:
                              const Text('This will not affect past bookings.'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref
                            .read(paymentMethodsProvider.notifier)
                            .remove(m.id);
                      }
                    },
                  ),
                  onTap: () => showEditor(existing: m),
                );
              },
            ),
    );
  }
}

class _MethodEditorSheet extends StatefulWidget {
  const _MethodEditorSheet({this.existing});

  final PaymentMethod? existing;

  @override
  State<_MethodEditorSheet> createState() => _MethodEditorSheetState();
}

class _MethodEditorSheetState extends State<_MethodEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
	  late final TextEditingController _label =
	      TextEditingController(text: widget.existing?.label ?? '');
	  late String _provider = widget.existing?.provider ?? 'mpesa_tz';
	  late String _phoneNumber = widget.existing?.phone ?? '';
	  late bool _isDefault = widget.existing?.isDefault ?? false;
	  String _countryCode = '+255';

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  String get _fullPhone {
    // existing phones are stored full-form already
    if (_phoneNumber.startsWith('+')) return _phoneNumber;
    return '$_countryCode$_phoneNumber';
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String fullPhone = _fullPhone;
    final PaymentMethod result = widget.existing == null
        ? PaymentMethod(
            id: '',
            label: _label.text.trim(),
            provider: _provider,
	            phone: fullPhone,
	            isDefault: _isDefault,
	          )
	        : widget.existing!.copyWith(
	            label: _label.text.trim(),
	            provider: _provider,
	            phone: fullPhone,
	            isDefault: _isDefault,
	          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;
    final String? initialNumber = widget.existing?.phone.startsWith('+255') ?? false
        ? widget.existing!.phone.replaceFirst('+255', '')
        : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg + insets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.existing == null ? 'Add payment method' : 'Edit method',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Personal, Work',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: PaymentMethod.providerLabels.entries
                  .map((MapEntry<String, String> e) =>
                      DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (String? v) {
                if (v != null) setState(() => _provider = v);
              },
            ),
            const SizedBox(height: 12),
	            IntlPhoneField(
              initialCountryCode: 'TZ',
              initialValue: initialNumber,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '712 345 678',
              ),
              onChanged: (PhoneNumber p) {
                _phoneNumber = p.number;
                _countryCode = p.countryCode;
              },
              validator: (PhoneNumber? phone) {
                final String number = phone?.number ?? '';
                if (number.length < 9) return 'Enter a valid phone number';
                return null;
	              },
	            ),
	            SwitchListTile(
	              contentPadding: EdgeInsets.zero,
	              title: const Text('Use as default'),
	              value: _isDefault,
	              onChanged: (bool value) => setState(() => _isDefault = value),
	            ),
	            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
