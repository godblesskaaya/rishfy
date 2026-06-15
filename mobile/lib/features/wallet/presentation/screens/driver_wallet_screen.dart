import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../../profile/domain/payment_method.dart';
import '../../../profile/presentation/providers/payment_methods_provider.dart';
import '../../data/models/wallet_models.dart';
import '../providers/wallet_provider.dart';

class DriverWalletScreen extends ConsumerWidget {
  const DriverWalletScreen({super.key});

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DriverWalletSnapshot> walletAsync =
        ref.watch(driverWalletProvider);
    final RequestPayoutState requestState = ref.watch(requestPayoutProvider);

    ref.listen<RequestPayoutState>(requestPayoutProvider,
        (RequestPayoutState? previous, RequestPayoutState next) {
      if (next.completed != null &&
          next.completed?.payoutId != previous?.completed?.payoutId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payout ${next.completed!.status.replaceAll('_', ' ')}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => unawaited(
                context.push('/driver/payouts/${next.completed!.payoutId}'),
              ),
            ),
          ),
        );
      }
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Driver wallet')),
      body: walletAsync.when(
        loading: () => const LoadingView(message: 'Loading wallet'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(driverWalletProvider),
        ),
        data: (DriverWalletSnapshot wallet) => RefreshIndicator(
          onRefresh: () async => ref.refresh(driverWalletProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            children: <Widget>[
              _BalanceSummary(stats: wallet.stats),
              const SizedBox(height: 16),
              _HeldBalanceNotice(stats: wallet.stats),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: requestState.loading || wallet.stats.availableTzs <= 0
                    ? null
                    : () => _confirmPayout(context, ref, wallet.stats),
                icon: requestState.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  wallet.stats.availableTzs <= 0
                      ? 'No balance available'
                      : 'Request ${_tzs(wallet.stats.availableTzs)}',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Payout history',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              if (wallet.payouts.isEmpty)
                const EmptyView(
                  title: 'No payouts yet',
                  subtitle: 'Requested payouts will appear here for review.',
                  icon: Icons.receipt_long_outlined,
                )
              else
                ...wallet.payouts.map(
                  (DriverPayout payout) => _PayoutHistoryTile(payout: payout),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPayout(
    BuildContext context,
    WidgetRef ref,
    DriverEarningsStats stats,
  ) async {
    final PaymentMethod? method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _PayoutMethodSheet(
        amountTzs: stats.availableTzs,
      ),
    );
    if (method == null) return;
    await ref.read(requestPayoutProvider.notifier).request(method);
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.stats});

  final DriverEarningsStats stats;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Available balance',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _tzs(stats.availableTzs),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: <Widget>[
              _MoneyMetric(label: 'Pending', value: _tzs(stats.pendingPayoutTzs)),
              _MoneyMetric(label: 'Held', value: _tzs(stats.heldTzs)),
              _MoneyMetric(label: 'Paid out', value: _tzs(stats.paidOutTzs)),
              _MoneyMetric(label: 'Earned', value: _tzs(stats.totalEarnedTzs)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeldBalanceNotice extends StatelessWidget {
  const _HeldBalanceNotice({required this.stats});

  final DriverEarningsStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.heldTzs <= 0) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: scheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Some earnings are held while a safety, dispute, or admin review is open. Held money is not withdrawable yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyMetric extends StatelessWidget {
  const _MoneyMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _PayoutHistoryTile extends StatelessWidget {
  const _PayoutHistoryTile({required this.payout});

  final DriverPayout payout;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          payout.isCompleted
              ? Icons.check_circle_outline
              : payout.isFailed
                  ? Icons.error_outline
                  : Icons.schedule,
        ),
        title: Text(_tzs(payout.amountTzs)),
        subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(payout.requestedAt)),
        trailing: _PayoutStatusChip(status: payout.status),
        onTap: () => context.push('/driver/payouts/${payout.payoutId}'),
      ),
    );
  }
}

class _PayoutMethodSheet extends ConsumerStatefulWidget {
  const _PayoutMethodSheet({required this.amountTzs});

  final int amountTzs;

  @override
  ConsumerState<_PayoutMethodSheet> createState() => _PayoutMethodSheetState();
}

class _PayoutMethodSheetState extends ConsumerState<_PayoutMethodSheet> {
  PaymentMethod? _selected;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
	    final List<PaymentMethod> methods = ref.watch(paymentMethodsProvider);
	    final PaymentMethod? selected =
	        _selected ?? _defaultMethod(methods);
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg + insets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Confirm payout',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _tzs(widget.amountTzs),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          if (methods.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Add a mobile money method before requesting a payout.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/profile/payment-methods');
                  },
                  icon: const Icon(Icons.add_card),
                  label: const Text('Add payment method'),
                ),
              ],
            )
          else ...<Widget>[
            Text('Send to', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...methods.map(
              (PaymentMethod method) => RadioListTile<PaymentMethod>(
                value: method,
                groupValue: selected,
                title: Text(
                  method.label.isEmpty
                      ? method.providerDisplayName
                      : method.label,
                ),
                subtitle: Text('${method.providerDisplayName} · ${method.phone}'),
                onChanged: (PaymentMethod? value) {
                  if (value != null) setState(() => _selected = value);
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                selected == null ? null : () => Navigator.pop(context, selected),
            child: const Text('Request payout'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
	  }

	  PaymentMethod? _defaultMethod(List<PaymentMethod> methods) {
	    if (methods.isEmpty) return null;
	    for (final PaymentMethod method in methods) {
	      if (method.isDefault) return method;
	    }
	    return methods.first;
	  }
	}

class _PayoutStatusChip extends StatelessWidget {
  const _PayoutStatusChip({required this.status});

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
    return Chip(
      label: Text(status.replaceAll('_', ' ')),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color, fontSize: 12),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }
}
