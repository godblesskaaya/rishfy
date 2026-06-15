import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../data/models/wallet_models.dart';
import '../providers/wallet_provider.dart';

class PayoutDetailScreen extends ConsumerWidget {
  const PayoutDetailScreen({required this.payoutId, super.key});

  final String payoutId;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DriverPayoutDetail> payoutAsync =
        ref.watch(driverPayoutDetailProvider(payoutId));

    return Scaffold(
      appBar: AppBar(title: const Text('Payout detail')),
      body: payoutAsync.when(
        loading: () => const LoadingView(message: 'Loading payout'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(driverWalletProvider),
        ),
        data: (DriverPayoutDetail detail) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(driverPayoutDetailProvider(payoutId));
            await ref.refresh(driverWalletProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            children: <Widget>[
              Builder(builder: (BuildContext context) {
                final DriverPayout payout = detail.payout;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
              Text(
                _tzs(payout.amountTzs),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              _StatusChip(status: payout.status),
              const SizedBox(height: 24),
              _DetailRow(label: 'Payout ID', value: payout.payoutId),
              _DetailRow(label: 'Method', value: payout.payoutMethod),
              _DetailRow(label: 'Phone', value: payout.payoutPhone),
              _DetailRow(
                label: 'Requested',
                value: DateFormat('dd MMM yyyy, HH:mm').format(payout.requestedAt),
              ),
              if (payout.completedAt != null)
                _DetailRow(
                  label: 'Completed',
                  value: DateFormat('dd MMM yyyy, HH:mm')
                      .format(payout.completedAt!),
                ),
              if (payout.providerReference != null)
                _DetailRow(
                  label: 'Provider reference',
                  value: payout.providerReference!,
                ),
              const SizedBox(height: 24),
              Text(
                'Timeline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _TimelineStep(
                title: 'Requested',
                subtitle: 'Your payout request was submitted.',
                active: true,
              ),
              _TimelineStep(
                title: 'Review',
                subtitle: 'Rishfy checks payout eligibility and any open holds.',
                active: payout.status != 'failed' && payout.status != 'cancelled',
              ),
              _TimelineStep(
                title: 'Processing',
                subtitle: 'Funds are being sent to your mobile money account.',
                active: payout.status == 'processing' || payout.status == 'completed',
              ),
              _TimelineStep(
                title: payout.isCompleted ? 'Completed' : 'Completed or failed',
                subtitle: payout.isCompleted
                    ? 'Funds were marked as paid out.'
                    : 'Final provider status will appear here.',
                active: payout.isCompleted || payout.isFailed,
              ),
                  ],
                );
              }),
              if (detail.items.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                _DetailSection(
                  title: 'Payout items',
                  children: detail.items
                      .map((PayoutItem item) => _DetailRow(
                            label: item.bookingId == null ? 'Ledger item' : 'Booking',
                            value: item.bookingId == null
                                ? _tzs(item.amountTzs)
                                : '${item.bookingId} · ${_tzs(item.amountTzs)}',
                          ))
                      .toList(),
                ),
              ],
              if (detail.holds.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Holds',
                  children: detail.holds
                      .map((PayoutHold hold) => _DetailRow(
                            label: hold.active ? 'Active hold' : 'Released hold',
                            value:
                                '${hold.reason.replaceAll('_', ' ')} · ${_tzs(hold.amountTzs)}',
                          ))
                      .toList(),
                ),
              ],
              if (detail.ledgerJournals.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Ledger',
                  children: detail.ledgerJournals
                      .map((PayoutLedgerJournal journal) => _DetailRow(
                            label: journal.journalType.replaceAll('_', ' '),
                            value:
                                '${journal.entries.length} entries · ${DateFormat('dd MMM yyyy, HH:mm').format(journal.createdAt)}',
                          ))
                      .toList(),
                ),
              ],
              if (detail.reconciliationRecords.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Reconciliation',
                  children: detail.reconciliationRecords
                      .map((PayoutReconciliationRecord record) => _DetailRow(
                            label: record.provider,
                            value:
                                '${record.matchStatus.replaceAll('_', ' ')} · ${record.providerReference}',
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = active ? scheme.primary : scheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool completed = status == 'completed';
    final bool failed = status == 'failed' || status == 'cancelled';
    final Color color = completed
        ? scheme.primary
        : failed
            ? scheme.error
            : scheme.tertiary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        label: Text(status.replaceAll('_', ' ')),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        labelStyle: TextStyle(color: color),
        backgroundColor: color.withValues(alpha: 0.08),
      ),
    );
  }
}
