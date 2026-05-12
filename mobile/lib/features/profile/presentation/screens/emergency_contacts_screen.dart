import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/emergency_contact.dart';
import '../providers/emergency_contacts_provider.dart';

class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<EmergencyContact> contacts =
        ref.watch(emergencyContactsProvider);

    Future<void> showEditor({EmergencyContact? existing}) async {
      final EmergencyContact? result =
          await showModalBottomSheet<EmergencyContact>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ContactEditorSheet(existing: existing),
      );
      if (result == null) return;
      if (existing == null) {
        await ref
            .read(emergencyContactsProvider.notifier)
            .add(
              name: result.name,
              phone: result.phone,
              relationship: result.relationship,
            );
      } else {
        await ref.read(emergencyContactsProvider.notifier).update(result);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showEditor,
        icon: const Icon(Icons.add),
        label: const Text('Add contact'),
      ),
      body: contacts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.contact_phone, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'No emergency contacts yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save up to a few trusted people. You can quickly '
                      'copy their numbers from the in-trip emergency dialog.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext ctx, int i) {
                final EmergencyContact c = contacts[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(_initials(c.name))),
                  title: Text(c.name),
                  subtitle: Text(
                    c.relationship == null
                        ? c.phone
                        : '${c.phone} · ${c.relationship}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Copy number',
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: c.phone),
                          );
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Number copied')),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final bool? ok = await showDialog<bool>(
                            context: ctx,
                            builder: (BuildContext dCtx) => AlertDialog(
                              title: const Text('Delete contact?'),
                              content: Text('Remove ${c.name} from your emergency contacts?'),
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
                                .read(emergencyContactsProvider.notifier)
                                .remove(c.id);
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () => showEditor(existing: c),
                );
              },
            ),
    );
  }
}

String _initials(String name) {
  final List<String> parts =
      name.trim().split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _ContactEditorSheet extends StatefulWidget {
  const _ContactEditorSheet({this.existing});

  final EmergencyContact? existing;

  @override
  State<_ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<_ContactEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _relationship = TextEditingController(
    text: widget.existing?.relationship ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final EmergencyContact result = widget.existing == null
        ? EmergencyContact(
            id: '',
            name: _name.text,
            phone: _phone.text,
            relationship: _relationship.text,
          )
        : widget.existing!.copyWith(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            relationship: _relationship.text.trim().isEmpty
                ? null
                : _relationship.text.trim(),
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;
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
              widget.existing == null ? 'Add contact' : 'Edit contact',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (String? v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+255 712 345 678',
              ),
              validator: (String? v) {
                final String trimmed = (v ?? '').trim();
                if (trimmed.length < 7) return 'Enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relationship,
              decoration: const InputDecoration(
                labelText: 'Relationship (optional)',
                hintText: 'e.g. spouse, parent',
              ),
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
