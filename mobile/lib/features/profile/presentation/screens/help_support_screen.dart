import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../domain/support_case.dart';
import '../providers/profile_provider.dart';

class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  Future<void> _copy(BuildContext ctx, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  Future<void> _showNewCaseSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SupportCaseSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SupportCase>> casesAsync =
        ref.watch(supportCasesProvider);
    final SupportCaseActionState actionState =
        ref.watch(supportCaseActionProvider);

    ref.listen<SupportCaseActionState>(
      supportCaseActionProvider,
      (SupportCaseActionState? previous, SupportCaseActionState next) {
        if (previous?.status == next.status) return;
        if (next.status == SupportCaseActionStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Support case submitted.')),
          );
        }
        if (next.status == SupportCaseActionStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.error ?? 'Could not submit case.')),
          );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(supportCasesProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          children: <Widget>[
            Text(
              'How can we help?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Send a support case when an issue needs follow-up. For immediate danger, dial 112 first.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: actionState.status == SupportCaseActionStatus.loading
                  ? null
                  : () => _showNewCaseSheet(context, ref),
              icon: actionState.status == SupportCaseActionStatus.loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_comment_outlined),
              label: const Text('Create support case'),
            ),
            const SizedBox(height: 24),
            Text(
              'Recent cases',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            casesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(message: 'Loading support cases'),
              ),
              error: (Object error, _) => ErrorView.fromException(
                error,
                onRetry: () => ref.invalidate(supportCasesProvider),
              ),
              data: (List<SupportCase> cases) {
                if (cases.isEmpty) {
                  return const EmptyView(
                    icon: Icons.support_agent_outlined,
                    title: 'No support cases',
                    subtitle: 'Cases you submit will appear here with their status.',
                  );
                }
                return Column(
                  children: cases
                      .map(
                        (SupportCase supportCase) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SupportCaseCard(supportCase: supportCase),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Quick contacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _ContactCard(
              icon: Icons.email_outlined,
              label: 'Email',
              value: 'support@rishfy.co',
              onCopy: () => _copy(context, 'support@rishfy.co'),
            ),
            const SizedBox(height: 8),
            _ContactCard(
              icon: Icons.chat_bubble_outline,
              label: 'WhatsApp',
              value: '+255 712 345 678',
              onCopy: () => _copy(context, '+255712345678'),
            ),
            const SizedBox(height: 8),
            _ContactCard(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: '+255 22 211 1111',
              onCopy: () => _copy(context, '+255222111111'),
            ),
            const SizedBox(height: 24),
            Text(
              'Frequently asked questions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._faq.map(
              (_FaqEntry entry) => Card(
                child: ExpansionTile(
                  title: Text(entry.question),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(entry.answer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'For emergencies, dial 112.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SupportCaseSheet extends ConsumerStatefulWidget {
  const _SupportCaseSheet();

  @override
  ConsumerState<_SupportCaseSheet> createState() => _SupportCaseSheetState();
}

class _SupportCaseSheetState extends ConsumerState<_SupportCaseSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _bookingId = TextEditingController();
  String _category = 'general';

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _bookingId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(supportCaseActionProvider.notifier).create(
          subject: _subject.text.trim(),
          message: _message.text.trim(),
          category: _category,
          bookingId: _bookingId.text.trim().isEmpty
              ? null
              : _bookingId.text.trim(),
        );
    final SupportCaseActionState state = ref.read(supportCaseActionProvider);
    if (state.status == SupportCaseActionStatus.success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;
    final SupportCaseActionState actionState =
        ref.watch(supportCaseActionProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg + insets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Create support case',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'general', child: Text('General')),
                  DropdownMenuItem(value: 'trip', child: Text('Trip')),
                  DropdownMenuItem(
                    value: 'payment_refund',
                    child: Text('Payment or refund'),
                  ),
                  DropdownMenuItem(value: 'safety', child: Text('Safety')),
                  DropdownMenuItem(value: 'account', child: Text('Account')),
                ],
                onChanged: (String? value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subject,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Short summary',
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.length < 3) return 'Enter a subject';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                minLines: 4,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Tell us what happened and what you need.',
                  alignLabelWithHint: true,
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.length < 10) return 'Add more detail';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bookingId,
                decoration: const InputDecoration(
                  labelText: 'Booking ID (optional)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: actionState.status == SupportCaseActionStatus.loading
                    ? null
                    : _submit,
                icon: actionState.status == SupportCaseActionStatus.loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Submit case'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportCaseCard extends StatelessWidget {
  const _SupportCaseCard({required this.supportCase});

  final SupportCase supportCase;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateFormat formatter = DateFormat('d MMM yyyy, HH:mm');
    final Color statusColor =
        supportCase.isOpen ? scheme.primary : scheme.outline;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    supportCase.subject,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _CaseChip(
                  label: supportCase.status.replaceAll('_', ' '),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              supportCase.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                _CaseChip(
                  label: supportCase.category.replaceAll('_', ' '),
                  color: scheme.secondary,
                ),
                _CaseChip(
                  label: supportCase.priority,
                  color: _priorityColor(context, supportCase.priority),
                ),
                Text(
                  formatter.format(supportCase.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityColor(BuildContext context, String priority) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (priority == 'urgent' || priority == 'high') return scheme.error;
    return scheme.tertiary;
  }
}

class _CaseChip extends StatelessWidget {
  const _CaseChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        subtitle: Text(value),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
      ),
    );
  }
}

class _FaqEntry {
  const _FaqEntry({required this.question, required this.answer});
  final String question;
  final String answer;
}

const List<_FaqEntry> _faq = <_FaqEntry>[
  _FaqEntry(
    question: 'How do I book a ride?',
    answer:
        'From the home screen, tap "Where to?" and search for a route. '
        'Choose a matching ride, confirm seats, enter your mobile money '
        'number, and approve the payment prompt on your phone.',
  ),
  _FaqEntry(
    question: 'How do drivers get verified?',
    answer:
        'Drivers submit their licence number, expiry, and optional LATRA '
        'permit through the "Become a driver" flow. All routes are posted '
        'against a verified vehicle on the driver profile.',
  ),
  _FaqEntry(
    question: 'How is the price calculated?',
    answer:
        'Drivers set a flat price per seat when they post a route. The '
        'total you pay equals price-per-seat times the number of seats '
        'you book. Rishfy adds no surcharges at booking time.',
  ),
  _FaqEntry(
    question: 'Can I cancel a booking?',
    answer:
        'Yes. Open the booking and tap "Cancel booking". Free cancellation '
        'is available before boarding. Refunds may be automated or routed '
        'for manual review depending on provider support.',
  ),
  _FaqEntry(
    question: 'How do I report a problem during a trip?',
    answer:
        'During an active trip, tap the red emergency icon. For immediate '
        'danger, call 112 first, then submit a trip safety report in the app.',
  ),
  _FaqEntry(
    question: 'Where is my data stored?',
    answer:
        'Your account data is stored on Rishfy systems. Tokens and sensitive '
        'local data are kept in secure device storage where applicable.',
  ),
];
